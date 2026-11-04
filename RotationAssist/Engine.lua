local _, NS = ...
local RA = NS.RA

-- The secure side. One rotation button runs the active rotation's macro for the current mode; a mode button moves
-- to the next mode (casting or cancelling the toggle spell on the way) and Steps blocks get a button each that
-- moves one line per press. All of it is set up out of combat. In combat only the secure snippets below change
-- anything, and only on a key press or a state driver.
local Engine = {}
RA.Engine = Engine

Engine.BUTTON, Engine.TOGGLE = "RotationAssistButton", "RotationAssistToggle"
Engine.pending = false

local exec, toggle
local stepButtons = {}
local shownModes, shownSteps = 0, {}

-- Runs in the restricted environment when the mode state driver changes.
local STATE_SNIPPET = [[
local mode = tonumber(newstate)
if mode and self:GetAttribute("mt" .. mode) then
	self:SetAttribute("modeindex", mode)
	self:SetAttribute("macrotext", self:GetAttribute("mt" .. mode))
end
]]

-- Before the mode button's click: move the rotation button to the next mode and set this button's own macro to
-- what entering that mode casts (or nothing).
local TOGGLE_SNIPPET = [[
local exec = self:GetFrameRef("exec")
local count = tonumber(exec:GetAttribute("modecount")) or 1
local mode = (tonumber(exec:GetAttribute("modeindex")) or 1) % count + 1
exec:SetAttribute("modeindex", mode)
exec:SetAttribute("macrotext", exec:GetAttribute("mt" .. mode))
self:SetAttribute("macrotext", self:GetAttribute("enter" .. mode) or "")
]]

-- Before a Steps button's click: the next line, wrapping around.
local STEP_SNIPPET = [[
local count = tonumber(self:GetAttribute("count")) or 0
if count > 0 then
	local i = (tonumber(self:GetAttribute("i")) or 0) % count + 1
	self:SetAttribute("i", i)
	self:SetAttribute("macrotext", self:GetAttribute("s" .. i))
end
]]
Engine.SNIPPETS = { state = STATE_SNIPPET, toggle = TOGGLE_SNIPPET, step = STEP_SNIPPET }

local function create()
	exec = CreateFrame("Button", Engine.BUTTON, UIParent, "SecureActionButtonTemplate,SecureHandlerStateTemplate")
	exec:RegisterForClicks("AnyUp")
	exec:SetAttribute("type", "macro")
	exec:SetAttribute("macrotext", "")
	exec:SetAttribute("modecount", 1)
	exec:SetAttribute("modeindex", 1)
	exec:SetAttribute("_onstate-sramode", STATE_SNIPPET)
	exec:Hide()

	toggle = CreateFrame("Button", Engine.TOGGLE, UIParent, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
	toggle:RegisterForClicks("AnyUp")
	toggle:SetAttribute("type", "macro")
	toggle:SetAttribute("macrotext", "")
	SecureHandlerSetFrameRef(toggle, "exec", exec)
	SecureHandlerWrapScript(toggle, "OnClick", toggle, TOGGLE_SNIPPET)
	toggle:Hide()
end

local function stepButton(n)
	local b = stepButtons[n]
	if not b then
		b = CreateFrame("Button", RA.Compiler.STEP_BUTTON .. n, UIParent, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
		b:RegisterForClicks("AnyUp")
		b:SetAttribute("type", "macro")
		SecureHandlerWrapScript(b, "OnClick", b, STEP_SNIPPET)
		b:Hide()
		stepButtons[n] = b
	end
	return b
end

-- The rotation and mode buttons, made on first use (at login, by whichever file asks first).
function Engine.Buttons()
	if not exec then create() end
	return exec, toggle
end

function Engine.ModeIndex()
	return exec and tonumber(exec:GetAttribute("modeindex")) or 1
end

function Engine.ModeCount()
	return exec and tonumber(exec:GetAttribute("modecount")) or 1
end

-- With a toggle spell, mode 1 is "spell off" and mode 2 "spell on": the mode that matches the player's auras.
local function auraMode(compiled)
	local spell = compiled and compiled.toggle and compiled.toggle.spell
	local mode
	if spell and UnitBuff then mode = UnitBuff("player", spell) and 2 or 1 end
	return mode
end

local function setMode(mode)
	exec:SetAttribute("modeindex", mode)
	exec:SetAttribute("macrotext", exec:GetAttribute("mt" .. mode) or "")
end

-- Out of combat only: puts the active rotation (or nothing) on the buttons.
local function apply()
	local rotation = RA:ActiveRotation()
	local compiled = rotation and RA.Compiler.Compile(rotation) or nil
	local modes = compiled and compiled.modes or {}
	local count = math.max(1, #modes)
	local current = Engine.ModeIndex()

	UnregisterStateDriver(exec, "sramode")
	for i = 1, math.max(shownModes, count) do
		local mode = modes[i]
		exec:SetAttribute("mt" .. i, mode and mode.text or nil)
		toggle:SetAttribute("enter" .. i, compiled and compiled.toggle and compiled.toggle.enter[i] or nil)
	end
	if #modes == 0 then exec:SetAttribute("mt1", "") end
	shownModes = count
	exec:SetAttribute("modecount", count)
	setMode(auraMode(compiled) or (current <= count and current) or 1)
	toggle:SetAttribute("macrotext", "")

	local steps = compiled and compiled.steps or {}
	for n = 1, math.max(#shownSteps, #steps) do
		local b = stepButton(n)
		local old = shownSteps[n] or 0
		local lines = steps[n] and steps[n].lines or {}
		for i = 1, math.max(old, #lines) do b:SetAttribute("s" .. i, lines[i]) end
		b:SetAttribute("count", #lines)
		b:SetAttribute("i", 0)
		b:SetAttribute("macrotext", "")
		shownSteps[n] = #lines
	end
	if compiled and compiled.rule then RegisterStateDriver(exec, "sramode", compiled.rule) end

	Engine.compiled, Engine.rotation = compiled, rotation
	Engine.pending = false
	if RA.Keys then RA.Keys.Apply() end
	if RA.RotationButton then RA.RotationButton.Refresh() end
	if RA.Window then RA.Window.Refresh() end
end

-- Rebuilds the buttons now, or once combat ends.
function Engine.Apply()
	if InCombatLockdown() then
		Engine.pending = true
		if RA.Window then RA.Window.Refresh() end
	else
		apply()
	end
end

-- Coalesces bursts of changes (spellbook events, typing in the editor) into one rebuild on the next frame.
local driver = CreateFrame("Frame")
function Engine.Request()
	driver.requested = true
end
driver:SetScript("OnUpdate", function(self)
	if self.requested and exec then
		self.requested = false
		Engine.Apply()
	end
end)

-- Out of combat, a toggle spell that dropped (or was cast from the spellbook) puts the mode back in step.
local function resync()
	local mode = auraMode(Engine.compiled)
	if mode and mode ~= Engine.ModeIndex() and not InCombatLockdown() and mode <= Engine.ModeCount() then
		setMode(mode)
		if RA.RotationButton then RA.RotationButton.Refresh() end
	end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "SPELLS_CHANGED",
	"LEARNED_SPELL_IN_TAB", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE", "UNIT_AURA" }) do
	events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, unit)
	if event == "PLAYER_LOGIN" then
		Engine.Buttons()
		Engine.Apply()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if Engine.pending then Engine.Apply() else resync() end
		if RA.Window then RA.Window.Refresh() end
	elseif event == "PLAYER_REGEN_DISABLED" then
		if RA.RotationButton then RA.RotationButton.Lock() end
		if RA.Window then RA.Window.Refresh() end
	elseif event == "UNIT_AURA" then
		if unit == "player" then resync() end
	else
		Engine.Request()
	end
end)
