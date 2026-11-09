local _, NS = ...
local RA = NS.RA

-- The Preview tab: the macro each mode turns into on this character, with its length, what was skipped and any
-- warnings. The text can be selected and copied; typing in it changes nothing.
local Editor = {}
RA.PreviewEditor = Editor

local S = RA.Style
local C = S.colors

local frame

local function previewText(rotation, compiled)
	local parts = {}
	for i, mode in ipairs(compiled.modes) do
		local label = rotation.modes[i].label ~= "" and rotation.modes[i].label or ("Mode " .. i)
		parts[#parts + 1] = S.Hex(C.heading, ("%d. %s"):format(i, label)) .. "  " ..
			S.Hex(#mode.text > RA.Compiler.MAX_MACRO and C.bad or C.muted, ("%d / %d Characters"):format(#mode.text, RA.Compiler.MAX_MACRO))
		for _, w in ipairs(mode.warnings) do parts[#parts + 1] = S.Hex(C.warn, w) end
		if #mode.skipped > 0 then
			parts[#parts + 1] = S.Hex(C.muted, "Not known here, left out: " .. table.concat(mode.skipped, ", "))
		end
		parts[#parts + 1] = mode.text
		parts[#parts + 1] = ""
	end
	for n, step in ipairs(compiled.steps) do
		if step.solo then
			parts[#parts + 1] = S.Hex(C.heading, ("No-Target Cast %d"):format(n)) .. "  " .. S.Hex(C.muted, "only when Smart Picks picks it, out of combat with nothing targeted")
			parts[#parts + 1] = step.solo
		else
			parts[#parts + 1] = S.Hex(C.heading, (step.cycle and "One Spell per Press %d" or "Steps Block %d"):format(n)) .. "  " .. S.Hex(C.muted, "one line per press")
			for i, line in ipairs(step.lines) do parts[#parts + 1] = ("%d: %s"):format(i, line) end
		end
		parts[#parts + 1] = ""
	end
	if compiled.toggle then
		parts[#parts + 1] = S.Hex(C.heading, "Mode Key")
		for i = 1, #compiled.modes do
			parts[#parts + 1] = ("Entering %d: %s"):format(i, compiled.toggle.enter[i] or "switch only")
		end
	elseif compiled.rule then
		parts[#parts + 1] = S.Hex(C.heading, "Condition Rule") .. "  " .. compiled.rule
	end
	for _, w in ipairs(compiled.warnings) do parts[#parts + 1] = S.Hex(C.warn, w) end
	return table.concat(parts, "\n")
end

function Editor.Create(parent, width, height)
	frame = RA.Widgets.TextArea(parent, "RotationAssistPreview", width, height, function()
		frame.edit:SetText(frame.text or "")
	end, "edit")
	return frame
end

function Editor.Render(rotation)
	local compiled = RA.Compiler.Compile(rotation)
	frame.text = previewText(rotation, compiled)
	frame.edit:SetText(frame.text)
	local warnings = #compiled.warnings
	for _, mode in ipairs(compiled.modes) do warnings = warnings + #mode.warnings end
	return warnings > 0 and S.Hex(C.warn, S.Count(warnings, "Warning")) or "What the Button Runs on This Character"
end
