local _, NS = ...
local RA = NS.RA

-- The Modes tab: the rotation's modes (names and order) on the left; how the button switches between them and
-- what every press does on the right.
local Editor = {}
RA.ModeEditor = Editor

local S = RA.Style
local C = S.colors
local W = RA.Widgets
local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H
local ROW_H = CONTROL_H + 6
local LEFT_W = 300
local UP_W, DOWN_W, REMOVE_W = 36, 44, 60
local OPTION_H = CONTROL_H + 14

local frame

local SWITCHES = {
	{ value = "none", text = "No Switching", tooltip = "The button always runs mode 1." },
	{ value = "toggle", text = "Mode Key", tooltip = "Each press of the Mode key (or the small button) goes to the next mode, in or out of combat. It can cast a spell on the way, like a form." },
	{ value = "rule", text = "Condition Rule", tooltip = "Modes switch by themselves, in combat too, on anything a macro condition can see: forms, stances, modifier keys, the target." },
}
local SWITCH_HELP = {
	none = "Add a second mode to switch between them.",
	toggle = "Without a spell the Mode key only cycles modes. With one, mode 2 casts it and mode 1 cancels it, so mode 1 is without it and mode 2 with it. Out of combat the mode follows the buff.",
	rule = "Conditions, then the mode number, like [form:4] 2; 1 for a form on the fourth stance button. Macro conditions can't see buffs or procs; use triggers for those.",
}
local OPTIONS = {
	{ key = "target", label = "Target the Nearest Enemy", note = "When you have no target, or a dead one.", tip = "When you have no target (or a dead one), the press targets the nearest enemy first." },
	{ key = "attack", label = "Start Auto-Attack", note = "Melee or ranged, on a living enemy.", tip = "Each press starts melee or ranged auto-attack on a living enemy." },
	{ key = "pet", label = "Send the Pet to Attack", note = "At your target.", tip = "Each press sends your pet at your target." },
	{ key = "channels", label = "Don't Interrupt Channels", note = "Mashing can't cut a spell like Blizzard short.", tip = "Presses do nothing while you channel a spell like Blizzard, so mashing can't cut it short." },
	{ key = "cycle", label = "One Spell per Press", note = "One GCD spell a press, top ones most often.", tip = "Each press tries only the next spell on the global cooldown, in GSE's priority order (1, 1 2, 1 2 3...), so the top ones come up most. Off-GCD lines still fire every press. Without Smart Picks, a spell waiting on something the macro can't see (like runes) stops the rest of a press, so a plain list never gets past it." },
	{ key = "smart", label = "Smart Picks", note = "Skips what isn't ready; a met trigger goes first.", tip = "Each press casts the spell the Rotation Button shows: the first one that's really ready (cooldowns, runes, power, combo points, range, and no cast times while you move), except that a ready spell whose trigger is met goes first. It works by clearing your target for an instant before a line that could cast instead, so target frames can flicker while you mash. It needs a target to cast, so it doesn't suit healing or buffing friends: use One Spell per Press or a plain list there. Replaces One Spell per Press." },
}

local function edit(fn)
	local rotation = RA.Window.Selected()
	if rotation then
		fn(rotation)
		RA.Window.Edited()
	end
end

local function newRow(parent, i)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(LEFT_W, ROW_H)
	row.number = S.Text(row, "normal", C.muted)
	row.number:SetPoint("LEFT", 0, 0)
	row.number:SetText(i)
	local inputW = LEFT_W - 18 - UP_W - DOWN_W - REMOVE_W - 3 * GAP
	row.input = S.Input(row, "RotationAssistModeName" .. i, inputW, "Mode " .. i, 24)
	row.input:SetPoint("LEFT", 18, 0)
	row.input:SetScript("OnTextChanged", function(self, userInput)
		self:UpdatePlaceholder()
		if userInput then edit(function(r) r.modes[i].label = self:GetText() end) end
	end)
	row.up = S.Button(row, "Up", "secondary", UP_W, function()
		edit(function(r) RA.Rotation.Move(r.modes, i, -1) end)
	end, "Move this mode earlier. Mode numbers in a Condition Rule don't follow.")
	row.up:SetPoint("LEFT", row.input, "RIGHT", GAP, 0)
	row.down = S.Button(row, "Down", "secondary", DOWN_W, function()
		edit(function(r) RA.Rotation.Move(r.modes, i, 1) end)
	end, "Move this mode later. Mode numbers in a Condition Rule don't follow.")
	row.down:SetPoint("LEFT", row.up, "RIGHT", GAP, 0)
	row.remove = S.Button(row, "Remove", "danger", REMOVE_W, function()
		edit(function(r)
			table.remove(r.modes, i)
			RA.Window.state.mode = 1
		end)
	end)
	row.remove:SetPoint("LEFT", row.down, "RIGHT", GAP, 0)
	return row
end

function Editor.Create(parent, width, height)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width, height)
	frame = f

	local modes = W.Heading(f, "Modes")
	modes:SetPoint("TOPLEFT", 0, 0)
	f.rows = {}
	for i = 1, RA.Rotation.MAX_MODES do
		local row = newRow(f, i)
		row:SetPoint("TOPLEFT", 0, -(16 + (i - 1) * ROW_H))
		f.rows[i] = row
	end
	f.addMode = S.Button(f, "Add Mode", "secondary", 90, function()
		edit(function(r) RA.Rotation.AddMode(r, "") end)
	end, "Another list of actions, like an AoE mode or a mode for a form.")
	f.modesHelp = S.Text(f, "small", C.muted)
	f.modesHelp:SetWidth(LEFT_W)
	f.modesHelp:SetJustifyH("LEFT")
	f.modesHelp:SetText("Each mode is its own priority list on the Actions tab. A Condition Rule switches by these numbers, so moving a mode changes which rule value picks it.")

	-- centered on the old 1px line, on whole pixels whatever the skin's width
	local divider, dividerW = S.VerticalDivider(f)
	local dividerX = LEFT_W + PAD - math.floor((dividerW - 1) / 2)
	divider:SetPoint("TOPLEFT", dividerX, 0)
	divider:SetPoint("BOTTOMLEFT", dividerX, 0)

	local rightX = LEFT_W + 2 * PAD + 1
	local rightW = width - rightX
	local switching = W.Heading(f, "Switching Modes")
	switching:SetPoint("TOPLEFT", rightX, 0)
	f.switch = S.Dropdown(f, rightW, function(value)
		edit(function(r)
			r.switch = r.switch or {}
			r.switch.kind = value
		end)
	end)
	f.switch:SetPoint("TOPLEFT", rightX, -16)
	f.switch:SetOptions(SWITCHES)
	f.valueLabel = S.Text(f, "small", C.muted)
	f.valueLabel:SetPoint("TOPLEFT", rightX, -(16 + CONTROL_H + GAP))
	f.value = S.Input(f, "RotationAssistSwitchValue", rightW, "", 200)
	f.value:SetPoint("TOPLEFT", rightX, -(16 + CONTROL_H + GAP + 16))
	f.value:SetScript("OnTextChanged", function(self, userInput)
		self:UpdatePlaceholder()
		if userInput then
			edit(function(r)
				if r.switch.kind == "toggle" then
					local text = RA.Spells.Trim(self:GetText())
					r.switch.spell = text ~= "" and RA.Spells.FromText(text) or nil
				else
					r.switch.rule = self:GetText()
				end
			end)
		end
	end)
	f.help = S.Text(f, "small", C.muted)
	f.help:SetWidth(rightW)
	f.help:SetJustifyH("LEFT")
	f.help:SetJustifyV("TOP")

	f.pressHeading = W.Heading(f, "Every Press")
	f.options = {}
	for i, opt in ipairs(OPTIONS) do
		local t = W.Toggle(f, opt.label, opt.tip, function(on)
			edit(function(r)
				r.options = r.options or {}
				r.options[opt.key] = on or nil
			end)
		end)
		t.note = S.Text(f, "small", C.muted)
		t.note:SetPoint("TOPLEFT", t, "BOTTOMLEFT", S.CHECK_H + GAP, 4)
		t.note:SetWidth(rightW - S.CHECK_H - GAP)
		t.note:SetJustifyH("LEFT")
		t.note:SetText(opt.note)
		f.options[i] = t
	end
	return f
end

local function setText(input, text)
	if not input.focused then
		input:SetText(text or "")
		input:UpdatePlaceholder()
	end
end

function Editor.Render(rotation)
	local count = #rotation.modes
	for i, row in ipairs(frame.rows) do
		local mode = rotation.modes[i]
		if mode then
			setText(row.input, mode.label)
			if i > 1 then row.up:Enable() else row.up:Disable() end
			if i < count then row.down:Enable() else row.down:Disable() end
			if count > 1 then row.remove:Enable() else row.remove:Disable() end
			row:Show()
		else
			row:Hide()
		end
	end
	frame.addMode:ClearAllPoints()
	frame.addMode:SetPoint("TOPLEFT", 18, -(16 + count * ROW_H))
	if count < RA.Rotation.MAX_MODES then frame.addMode:Enable() else frame.addMode:Disable() end
	frame.modesHelp:ClearAllPoints()
	frame.modesHelp:SetPoint("TOPLEFT", 0, -(16 + count * ROW_H + CONTROL_H + 2 * GAP))

	local switch = rotation.switch or { kind = "none" }
	local kind = count > 1 and switch.kind or "none"
	for _, opt in ipairs(SWITCHES) do
		if opt.value == switch.kind then frame.switch:SetText(opt.text) end
	end
	if count > 1 then frame.switch:Enable() else frame.switch:Disable() end
	local hasValue = kind == "toggle" or kind == "rule"
	if hasValue then
		frame.valueLabel:SetText(kind == "toggle" and "Spell the Mode Key Casts" or "Rule")
		frame.value.placeholder:SetText(kind == "toggle" and "None: Only Switch Modes" or "[form:3] 2; 1")
		setText(frame.value, kind == "toggle" and (switch.spell and RA.Spells.Name(switch.spell) or "") or switch.rule)
		frame.valueLabel:Show()
		frame.value:Show()
	else
		frame.valueLabel:Hide()
		frame.value:Hide()
	end
	frame.help:ClearAllPoints()
	frame.help:SetPoint("TOPLEFT", hasValue and frame.value or frame.switch, "BOTTOMLEFT", 0, -GAP)
	frame.help:SetText(SWITCH_HELP[kind])

	frame.pressHeading:ClearAllPoints()
	frame.pressHeading:SetPoint("TOPLEFT", frame.help, "BOTTOMLEFT", 0, -2 * GAP)
	local options = rotation.options or {}
	for i, t in ipairs(frame.options) do
		local key = OPTIONS[i].key
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", frame.pressHeading, "BOTTOMLEFT", 0, -(4 + (i - 1) * OPTION_H))
		t:SetChecked(options[key])
		-- Smart Picks replaces One Spell per Press, so that one is grayed out while it's on
		t:SetEnabled(not (key == "cycle" and options.smart))
	end

	local compiled = RA.Compiler.Compile(rotation)
	local summary = S.Count(count, "Mode")
	if compiled.warnings[1] then summary = summary .. "  " .. S.Hex(C.warn, compiled.warnings[1]) end
	return summary
end
