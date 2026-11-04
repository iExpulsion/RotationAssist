local _, NS = ...
local RA = NS.RA

-- The Actions tab: the selected mode's priority list on the left (top runs first), the selected action's details
-- on the right, and an Add row on top. Spells can be dragged in from the spellbook.
local Editor = {}
RA.ActionEditor = Editor

local S = RA.Style
local C = S.colors
local W = RA.Widgets
local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H
local LIST_W = 250

local frame
local PLACEHOLDERS = {
	spell = "Spell Name or ID",
	sequence = "Spells, Comma-Separated",
	steps = "First Step (More Below)",
	macro = "Macro Line, Like /use 13",
}

local function setText(input, text)
	if not input.focused then
		input:SetText(text or "")
		if input.UpdatePlaceholder then input:UpdatePlaceholder() end
	end
end

local function currentMode(rotation, state)
	if not rotation.modes[state.mode] then state.mode = 1 end
	return rotation.modes[state.mode]
end

local function selectedAction(rotation, state)
	local mode = currentMode(rotation, state)
	return mode.actions[state.action or 0], mode
end

local function insert(action)
	local rotation, state = RA.Window.Selected(), RA.Window.state
	local ok = rotation ~= nil and action ~= nil
	if ok then
		local mode = currentMode(rotation, state)
		local at = state.action and math.min(state.action + 1, #mode.actions + 1) or #mode.actions + 1
		table.insert(mode.actions, at, action)
		state.action = at
		RA.Window.Edited()
	end
	return ok
end

local function addFromCursor(kind, slot, book)
	local spell = RA.Spells.FromCursor(kind, slot, book)
	if spell then insert({ kind = "spell", spell = spell }) end
end

local function addTyped()
	local kind, text = frame.kind.value, RA.Spells.Trim(frame.input:GetText())
	local action
	if text == "" and (kind == "spell" or kind == "sequence") then
		RA.Window.Message(S.Hex(C.warn, "Type a Spell Name or ID First, or Drag One from Your Spellbook"))
	elseif kind == "spell" then
		action = { kind = "spell", spell = RA.Spells.FromText(text) }
	elseif kind == "sequence" then
		action = { kind = "sequence", spells = RA.Spells.ListFromText(text), reset = "" }
	elseif kind == "steps" then
		action = { kind = "steps", steps = text ~= "" and { text } or {} }
	else
		action = { kind = "macro", text = text }
	end
	if insert(action) then
		frame.input:SetText("")
		frame.input:ClearFocus()
	end
end

local function edit(fn)
	local rotation = RA.Window.Selected()
	local action = rotation and selectedAction(rotation, RA.Window.state)
	if action then
		fn(action)
		RA.Window.Edited()
	end
end

local function move(delta)
	local rotation, state = RA.Window.Selected(), RA.Window.state
	local mode = rotation and currentMode(rotation, state)
	if mode and state.action and RA.Rotation.Move(mode.actions, state.action, delta) then
		state.action = state.action + delta
		RA.Window.Edited()
	end
end

local function remove()
	local rotation, state = RA.Window.Selected(), RA.Window.state
	local mode = rotation and currentMode(rotation, state)
	if mode and state.action and mode.actions[state.action] then
		table.remove(mode.actions, state.action)
		state.action = math.min(state.action, #mode.actions)
		if state.action == 0 then state.action = nil end
		RA.Window.Edited()
	end
end

local function label(parent, text)
	local fs = S.Text(parent, "small", C.muted)
	fs:SetText(text)
	return fs
end

local function createDetail(parent, width, height)
	local d = CreateFrame("Frame", nil, parent)
	d:SetSize(width, height)
	S.Panel(d, C.panel, C.border)
	local inner = width - 2 * PAD

	d.title = S.Text(d, "normal")
	d.title:SetPoint("TOPLEFT", PAD, -PAD)
	d.title:SetWidth(inner)
	d.title:SetWordWrap(false)
	d.status = S.Text(d, "small", C.muted)
	d.status:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -4)
	d.status:SetWidth(inner)

	d.whenLabel = label(d, "Conditions")
	d.when = S.Input(d, "RotationAssistWhen", inner, "Always, or Like [harm] or [mod:shift]", 150, 2)
	d.when:SetScript("OnTextChanged", function(self, userInput)
		self:UpdatePlaceholder()
		if userInput then edit(function(a) a.when = self:GetText() end) end
	end)
	d.hintLabel = label(d, "Hint")
	d.hint = S.Input(d, "RotationAssistHint", inner, "None, or Like [buff:Freezing Fog]", 180, 3)
	d.hint:SetScript("OnTextChanged", function(self, userInput)
		self:UpdatePlaceholder()
		if userInput then edit(function(a) a.hint = self:GetText() end) end
	end)
	d.hint:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Hint", 1, 1, 1)
		GameTooltip:AddLine("While the hint holds and the spell is ready, the Rotation Button shows it first and glows. While it doesn't, the spell is passed over.", 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine("With Smart Picks on, presses cast what the button shows. Without it, presses still go down the list and the hint only changes the button.", 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("[buff:X]  [nobuff:X]: on you", 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine("[debuff:X]  [nodebuff:X<3]: yours on the target; <3 means under 3 seconds left", 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine("[anydebuff:X]  [noanydebuff:X]: on the target from anyone", 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine("[cast:X]  [nocast:X>30]: you cast it on this target this fight; >30 means over 30 seconds ago", 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine("[power>=40]  [hp<35]  [targethp<20]", 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine(("[enemies>=3]: enemies you've hit or that hit you in the last %d seconds, counting your target"):format(RA.Enemies.WINDOW), 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine("[without:Blood Plague>=1]: how many of those enemies don't have your Blood Plague, for spreading it", 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine("Commas mean and; [a][b] means a or b.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	d.hint:HookScript("OnLeave", function() GameTooltip:Hide() end)
	d.spellsLabel = label(d, "Spells")
	d.spells = S.Input(d, "RotationAssistSeqSpells", inner, "Spells, Comma-Separated", 250)
	d.spells:SetScript("OnEnterPressed", function(self)
		edit(function(a) a.spells = RA.Spells.ListFromText(self:GetText()) end)
		self:ClearFocus()
	end)
	d.spells:HookScript("OnEditFocusLost", function(self)
		edit(function(a) a.spells = RA.Spells.ListFromText(self:GetText()) end)
	end)
	d.resetLabel = label(d, "Reset")
	d.reset = S.Input(d, "RotationAssistSeqReset", inner, "Never, or Like target or combat/30", 60)
	d.reset:SetScript("OnTextChanged", function(self, userInput)
		self:UpdatePlaceholder()
		if userInput then edit(function(a) a.reset = self:GetText() end) end
	end)
	d.once = W.Toggle(d, "Once per Reset",
		"Casts each spell once, then stops until the sequence resets (on a new target, after combat). Without Smart Picks, good for diseases or a mark; with it, a hint like [nodebuff:Blood Plague] refreshes them when they fall off.",
		function(on) edit(function(a) a.once = on or nil end) end)
	d.offGcd = W.Toggle(d, "Off the Global Cooldown",
		"Runs before the other lines on every press, alongside whatever casts: trinkets, racials, Empower Rune Weapon.",
		function(on) edit(function(a) a.offGcd = on or nil end) end)
	d.textLabel = label(d, "Lines")
	d.text = W.TextArea(d, "RotationAssistActionText", inner, 110, function(text)
		edit(function(a)
			if a.kind == "steps" then
				local steps = {}
				for line in text:gmatch("[^\n]+") do steps[#steps + 1] = line end
				a.steps = steps
			else
				a.text = text
			end
		end)
	end)

	d.up = S.Button(d, "Move Up", "secondary", 70, function() move(-1) end, "Try this action earlier.")
	d.up:SetPoint("BOTTOMLEFT", PAD, PAD)
	d.down = S.Button(d, "Move Down", "secondary", 80, function() move(1) end, "Try this action later.")
	d.down:SetPoint("LEFT", d.up, "RIGHT", GAP, 0)
	d.remove = S.Button(d, "Remove", "danger", 70, remove)
	d.remove:SetPoint("BOTTOMRIGHT", -PAD, PAD)

	d.none = S.Text(d, "small", C.muted)
	d.none:SetPoint("TOPLEFT", PAD, -PAD)
	d.none:SetWidth(inner)
	d.none:SetText("Pick an action to change it.\n\nThe button tries actions from the top down on every press and casts the first one that's ready, so put what matters most first.\n\nDrag spells here from your spellbook, or type a name above.")
	return d
end

-- Stacks the controls this kind of action uses under the title, top to bottom.
local function layoutDetail(d, kind)
	local controls = {
		{ d.whenLabel, d.when, show = kind == "spell" or kind == "sequence" },
		{ d.hintLabel, d.hint, show = kind == "spell" },
		{ d.spellsLabel, d.spells, show = kind == "sequence" },
		{ d.resetLabel, d.reset, show = kind == "sequence" },
		{ d.once, show = kind == "sequence" },
		{ d.offGcd, show = kind == "spell" or kind == "macro" },
		{ d.textLabel, d.text, show = kind == "steps" or kind == "macro" },
	}
	local y = PAD + 16 + 4 + 12 + PAD
	for _, group in ipairs(controls) do
		for _, w in ipairs(group) do
			if group.show then
				w:ClearAllPoints()
				w:SetPoint("TOPLEFT", PAD, -y)
				w:Show()
				y = y + (w.GetHeight and w:GetHeight() or 12) + 4
			else
				w:Hide()
			end
		end
		if group.show then y = y + GAP - 4 end
	end
end

function Editor.Create(parent, width, height)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width, height)
	frame = f

	f.modes = S.Dropdown(f, width - 90 - 150 - 56 - 4 * GAP, function(index)
		S.Dismiss()
		RA.Window.state.mode = index
		RA.Window.state.action = nil
		RA.Window.Render()
	end)
	f.modes:SetPoint("TOPLEFT", 0, 0)

	f.add = S.Button(f, "Add", "secondary", 56, addTyped, "Add it under the selected action, or at the end.")
	f.add:SetPoint("TOPRIGHT", 0, 0)
	f.input = S.Input(f, "RotationAssistAddInput", 150, PLACEHOLDERS.spell, 250)
	f.input:SetPoint("RIGHT", f.add, "LEFT", -GAP, 0)
	f.input:SetScript("OnEnterPressed", addTyped)
	f.kind = S.Dropdown(f, 90, function(value)
		f.kind.value = value
		f.input.placeholder:SetText(PLACEHOLDERS[value])
		RA.Window.Render()
	end)
	f.kind:SetPoint("RIGHT", f.input, "LEFT", -GAP, 0)
	f.kind:SetOptions(RA.Rotation.KINDS)
	f.kind.value = "spell"

	local listTop = CONTROL_H + GAP
	local listH = height - listTop
	local well = CreateFrame("Frame", nil, f)
	well:SetPoint("TOPLEFT", 0, -listTop)
	well:SetSize(LIST_W, listH)
	S.Panel(well, C.well, C.border)
	f.list = RA.List.New(well, "RotationAssistActionList", LIST_W - 14, listH - 2, "content")
	f.list.scroll:SetPoint("TOPLEFT", 1, -1)
	-- dropping a spell on the empty part of the list adds it at the end
	f.list.content:EnableMouse(true)
	well:EnableMouse(true)
	for _, target in ipairs({ well, f.list.content }) do
		target:SetScript("OnReceiveDrag", function() addFromCursor(GetCursorInfo()) ClearCursor() end)
		target:SetScript("OnMouseUp", function()
			if GetCursorInfo() then
				addFromCursor(GetCursorInfo())
				ClearCursor()
			end
		end)
	end

	f.detail = createDetail(f, width - LIST_W - GAP, listH)
	f.detail:SetPoint("TOPLEFT", LIST_W + GAP, -listTop)
	return f
end

local STATUS = {
	skipped = function() return S.Hex(C.bad, "Not Known") end,
	partial = function() return S.Hex(C.warn, "Partly Known") end,
}

local function subText(action)
	local parts = {}
	local when = RA.Spells.Trim(action.when)
	if when ~= "" then parts[#parts + 1] = when end
	if action.kind == "sequence" and RA.Spells.Trim(action.reset) ~= "" then parts[#parts + 1] = "reset=" .. action.reset end
	if action.kind == "sequence" and action.once then parts[#parts + 1] = "Once" end
	if action.kind == "spell" and RA.Hints.Has(action.hint) then parts[#parts + 1] = "Hint " .. RA.Spells.Trim(action.hint) end
	if action.offGcd then parts[#parts + 1] = "Off-GCD" end
	return #parts > 0 and table.concat(parts, "  ") or nil
end

local function renderDetail(rotation, state, compiled)
	local d = frame.detail
	local action, mode = selectedAction(rotation, state)
	local controls = { d.title, d.status, d.up, d.down, d.remove }
	for _, w in ipairs(controls) do if action then w:Show() else w:Hide() end end
	if action then
		d.none:Hide()
		layoutDetail(d, action.kind)
		d.title:SetText(RA.Rotation.ActionText(action))
		local status = compiled.status[state.action]
		local kindText = ({ spell = "Spell", sequence = "Sequence", steps = "Steps", macro = "Macro" })[action.kind]
		local problems = action.kind == "spell" and RA.Hints.Problems(action.hint) or {}
		d.status:SetText(("%s %d of %d"):format(kindText, state.action, #mode.actions) .. (status == "skipped"
			and ("  " .. S.Hex(C.bad, "Skipped: Not Known on This Character")) or status == "partial"
			and ("  " .. S.Hex(C.warn, "Some Spells Not Known")) or "")
			.. (#problems > 0 and ("  " .. S.Hex(C.warn, problems[1])) or ""))
		setText(d.when, action.when)
		setText(d.hint, action.hint)
		setText(d.spells, RA.Spells.ListText(action.spells))
		setText(d.reset, action.reset)
		d.offGcd:SetChecked(action.offGcd)
		d.once:SetChecked(action.once)
		d.text:SetValue(action.kind == "steps" and table.concat(action.steps or {}, "\n") or action.text)
		d.textLabel:SetText(action.kind == "steps" and "Steps, One per Line (a Spell Name or a Macro Line)" or "Lines")
		if state.action > 1 then d.up:Enable() else d.up:Disable() end
		if state.action < #mode.actions then d.down:Enable() else d.down:Disable() end
	else
		layoutDetail(d, "none")
		d.none:Show()
	end
end

function Editor.Render(rotation, state)
	local mode = currentMode(rotation, state)
	local options = {}
	for i, m in ipairs(rotation.modes) do
		options[i] = { value = i, text = ("%d. %s"):format(i, m.label ~= "" and m.label or ("Mode " .. i)) }
	end
	frame.modes:SetOptions(options)
	frame.modes:SetText(options[state.mode].text)
	frame.kind:SetText(RA.Rotation.KINDS[1].text)
	for _, k in ipairs(RA.Rotation.KINDS) do
		if k.value == frame.kind.value then frame.kind:SetText(k.text) end
	end

	local compiled = RA.Compiler.CompileMode(rotation, mode, nil, 1)
	local list = frame.list
	list:Begin()
	for i, action in ipairs(mode.actions) do
		local status = STATUS[compiled.status[i]]
		list:Add({
			text = S.Hex(C.muted, i) .. "  " .. RA.Rotation.ActionText(action),
			sub = subText(action),
			icon = RA.Rotation.ActionIcon(action),
			status = status and status() or nil,
			selected = state.action == i,
			onClick = function()
				S.Dismiss()
				state.action = i
				RA.Window.Render()
			end,
			onDrop = function(kind, slot, book)
				state.action = i
				addFromCursor(kind, slot, book)
			end,
		})
	end
	list:End()
	renderDetail(rotation, state, compiled)

	local skipped = 0
	for _, s in pairs(compiled.status) do if s == "skipped" then skipped = skipped + 1 end end
	local summary
	if #mode.actions == 0 then
		summary = "Drag Spells from Your Spellbook, or Type a Name and Add"
	else
		summary = S.Count(#mode.actions, "Action") .. (skipped > 0 and ("  " .. S.Hex(C.warn, skipped .. " Not Known on This Character")) or "")
	end
	return summary
end
