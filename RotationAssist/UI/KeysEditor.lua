local _, NS = ...
local RA = NS.RA

-- The Settings view: the Rotation and Mode keys, action bar macros, the on-screen Rotation Button and Quiet
-- Errors. These are the same for every rotation; the keys are per character.
local Editor = {}
RA.KeysEditor = Editor

local S = RA.Style
local C = S.colors
local W = RA.Widgets
local GAP, CONTROL_H = S.GAP, S.CONTROL_H
local LABEL_W, ROW_H = 110, CONTROL_H + 6
local SCALES = { 0.75, 1, 1.25, 1.5, 2 }

local frame
local capturing

local KEYS = {
	{ key = "main", label = "Rotation Key", tip = "Casts the first ready action of the current mode. Click to set, then press the key you want." },
	{ key = "toggle", label = "Mode Key", tip = "Goes to the next mode, casting the Mode key's spell if the rotation has one. Click to set, then press the key you want." },
}

local function keyRow(parent, def)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(400, ROW_H)
	local label = S.Text(row, "small")
	label:SetPoint("LEFT", 0, 0)
	label:SetWidth(LABEL_W)
	label:SetText(def.label)
	row.set = S.Button(row, "", "secondary", 150, function()
		capturing = def.key
		RA.Window.Render()
		RA.Keys.Capture(function(key)
			capturing = nil
			if key then RA.Keys.Set(def.key, key) end
			RA.Window.Render()
		end)
	end, def.tip)
	row.set:SetPoint("LEFT", LABEL_W, 0)
	row.clear = S.Button(row, "Clear", "ghost", 56, function()
		RA.Keys.Set(def.key, nil)
		RA.Window.Render()
	end)
	row.clear:SetPoint("LEFT", row.set, "RIGHT", GAP, 0)
	row.def = def
	return row
end

function Editor.Create(parent, width, height)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width, height)
	frame = f

	local keys = W.Heading(f, "Keys on This Character")
	keys:SetPoint("TOPLEFT", 0, 0)
	f.rows = {}
	for i, def in ipairs(KEYS) do
		local row = keyRow(f, def)
		row:SetPoint("TOPLEFT", 0, -(16 + (i - 1) * ROW_H))
		f.rows[i] = row
	end
	local note = S.Text(f, "small", C.muted)
	note:SetPoint("TOPLEFT", 0, -(16 + #KEYS * ROW_H + 2))
	note:SetWidth(width)
	note:SetText("These keys take over whatever they're normally bound to while the addon is loaded. Each press casts at most one spell on the global cooldown, so press again for the next one.")
	f.macros = S.Button(f, "Make Action Bar Macros", "secondary", 170, function()
		RA.Window.Message(S.Hex(C.muted, RA.Keys.MakeMacros()))
	end, "Makes RA Rotation and RA Mode general macros that click the same buttons, and puts RA Rotation on your cursor to drop on a bar.")
	f.macros:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -GAP)

	local buttonHeading = W.Heading(f, "Rotation Button")
	buttonHeading:SetPoint("TOPLEFT", f.macros, "BOTTOMLEFT", 0, -2 * GAP)
	f.showButton = W.Toggle(f, "Show the Rotation Button", "A large button on screen with the likely next spell, the mode and the key. Clicking it is the same as pressing the Rotation key.",
		function(on) RA.RotationButton.SetShown(on) RA.Window.Render() end)
	f.showButton:SetPoint("TOPLEFT", buttonHeading, "BOTTOMLEFT", 0, -4)
	f.lockButton = W.Toggle(f, "Lock Its Position", "Unlocked, the button can be dragged out of combat; clicks only cast when it's locked.",
		function(on) RA.RotationButton.SetLocked(on) RA.Window.Render() end)
	f.lockButton:SetPoint("TOPLEFT", f.showButton, "BOTTOMLEFT", 0, 0)
	local scaleLabel = S.Text(f, "small")
	scaleLabel:SetPoint("TOPLEFT", f.lockButton, "BOTTOMLEFT", 0, -GAP - 6)
	scaleLabel:SetText("Size")
	f.scale = S.Dropdown(f, 90, function(value) RA.RotationButton.SetScale(value) RA.Window.Render() end)
	f.scale:SetPoint("LEFT", scaleLabel, "LEFT", 40, 0)
	local options = {}
	for i, s in ipairs(SCALES) do options[i] = { value = s, text = ("%d%%"):format(s * 100) } end
	f.scale:SetOptions(options)
	f.reset = S.Button(f, "Reset Position", "ghost", 100, function() RA.RotationButton.ResetPosition() end,
		"Put the button back under the middle of the screen.")
	f.reset:SetPoint("LEFT", f.scale, "RIGHT", GAP, 0)

	local errorHeading = W.Heading(f, "Errors")
	errorHeading:SetPoint("TOPLEFT", scaleLabel, "BOTTOMLEFT", 0, -3 * GAP)
	f.quiet = W.Toggle(f, "Quiet Errors", "Hides the red error text for a moment after each press, and turns off the spoken errors. Lines that can't cast yet fail on purpose, so without this every press shows \"Not ready yet\".",
		function(on) RA.Quiet.Set(on) RA.Window.Render() end)
	f.quiet:SetPoint("TOPLEFT", errorHeading, "BOTTOMLEFT", 0, -4)
	f.gcdHold = W.Toggle(f, "Hold Presses During the Global Cooldown", "With Smart Picks, presses during the global cooldown try nothing, so failed casts don't play their fizzle sound. It does this by clearing and restoring your target around every line, many times a second while you mash. Some servers disconnect you for that, so a server module may turn it off.",
		function(on) RA.db.gcdHold = on and true or false RA.Window.Render() end)
	f.gcdHold:SetPoint("TOPLEFT", f.quiet, "BOTTOMLEFT", 0, -4)
	return f
end

function Editor.Render()
	for _, row in ipairs(frame.rows) do
		local waiting = capturing == row.def.key
		row.set:SetLabel(waiting and "Press a Key..." or RA.Keys.Text(row.def.key))
		row.set:SetKind(waiting and "selected" or "secondary")
		if RA.Keys.Get(row.def.key) then row.clear:Enable() else row.clear:Disable() end
	end
	local db = RA.db.button
	frame.showButton:SetChecked(db.shown)
	frame.lockButton:SetChecked(db.locked)
	frame.scale:SetText(("%d%%"):format((db.scale or 1) * 100))
	frame.quiet:SetChecked(RA.db.quiet)
	frame.gcdHold:SetChecked(RA:HoldsDuringGcd())
	local summary
	if capturing then
		summary = S.Hex(C.accent, "Press a Key, or Esc to Cancel")
	elseif InCombatLockdown() then
		summary = S.Hex(C.warn, "Key and Button Changes Apply After Combat")
	else
		summary = "The Same for Every Rotation"
	end
	return summary
end
