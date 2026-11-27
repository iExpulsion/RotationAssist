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

-- Field guides shown on hover: a string is a paragraph (or a heading when it starts with "#"), a pair is the syntax
-- and what it means.
local CONDITIONS_GUIDE = {
	"Macro conditions the game checks as you press. When they don't hold, the line is skipped, and Smart Picks passes the spell over. A unit after @ casts the spell there instead of on your target.",
	"#Target",
	{ "[harm]  [help]", "an enemy or a friend" },
	{ "[exists]  [dead]", "you have a target; it's dead" },
	{ "[@player]  [@focus]  [@mouseover]", "cast on that unit" },
	{ "[@playerlocation]  [@cursor]  [@targetlocation]", "a ground spell where you stand, at the mouse or at your target, with a client mod that adds them (short: ploc, cur, tloc)" },
	"#You",
	{ "[mod:shift]  [mod:ctrl]  [mod:alt]", "while you hold that key" },
	{ "[combat]", "in combat" },
	{ "[stance:1]  [form:2]", "your stance, form or presence, by its number" },
	{ "[stealth]  [mounted]  [flying]  [swimming]", "what you're doing" },
	{ "[channeling]", "while you channel a spell" },
	{ "[spec:2]  [pet]  [group]  [equipped:Shields]", "your talent spec, pet, group or gear" },
	"#Combining",
	"Commas mean and: [mod:shift,@player]. Separate brackets mean or: [a][b]. \"no\" turns one around: [nocombat].",
}

local TRIGGER_GUIDE = {
	"Checked by Rotation Assist. While the trigger is met and the spell is ready, it goes first, wherever it is in the list, and the Rotation Button glows; with When Met set to Stay in Place, it's only allowed and keeps its place. While it isn't met, the spell is passed over. With Smart Picks on, that's what a press casts; without it, only the button changes.",
	"#On You",
	{ "[buff:X]  [nobuff:X]", "a buff on you" },
	{ "[selfdebuff:X]  [noselfdebuff:X]", "a debuff on you" },
	{ "[stacks:X>=5]", "stacks of a buff on you" },
	"#On the Target",
	{ "[debuff:X]  [nodebuff:X]", "your debuff on the target" },
	{ "[anydebuff:X]  [noanydebuff:X]", "anyone's debuff on the target" },
	{ "[debuffstacks:X<5]  [anydebuffstacks:X<5]", "stacks of your debuff, or anyone's" },
	{ "[cast:X]  [nocast:X]", "you cast X on this target this fight" },
	{ "[nodebuff:X<3]  [nocast:X>30]", "add a time: missing or under 3 seconds left; never cast or over 30 seconds ago" },
	"#Numbers",
	{ "[power>=40]", "your mana, rage, energy or runic power" },
	{ "[hp<35]  [targethp<20]", "your health or the target's, in percent" },
	{ "[combo>=5]", "combo points on the target" },
	{ "[enemies>=3]", ("enemies you've hit or that hit you in the last %d seconds, your target included"):format(RA.Enemies.WINDOW) },
	{ "[without:X>=1]", "how many of those enemies don't have your X, for spreading it" },
	"#Combining",
	"Compare with < <= > >= or =. Commas mean and; separate brackets mean or: [a][b].",
}

local PLACES = {
	{ value = "jump", text = "When Met: Jump Ahead",
		tooltip = "While the trigger is met, the spell is tried before everything else in the list. For procs and short windows, like Slam with [buff:Slam!]." },
	{ value = "keep", text = "When Met: Stay in Place",
		tooltip = "The trigger only allows the spell; it's tried in its place in the list, after the spells above it. For fillers, like a Sunder Armor that only stacks when nothing above it is ready." },
}

-- Names of what a spell with a met trigger goes ahead of: the actions above it the pick would otherwise try first
-- (spells with no trigger or that stay in place, and Sequence and Steps blocks). Off-GCD spells and once-per-reset
-- sequences aren't in the pick's list order.
function Editor.JumpsAhead(actions, index)
	local names = {}
	for i = 1, (index or 1) - 1 do
		local a = actions[i]
		local spell = a.kind == "spell" and not a.offGcd and (a.keep or not RA.Triggers.Has(a.trigger))
		local block = (a.kind == "sequence" and not a.once) or a.kind == "steps"
		if spell or block then names[#names + 1] = RA.Rotation.ActionText(a) end
	end
	return names
end

-- "A", "A and B", "A, B and C", "A, B, C and 2 more".
function Editor.NameList(names)
	local shown = math.min(#names, 3)
	local text = table.concat(names, ", ", 1, shown)
	if #names > shown then
		text = text .. (" and %d more"):format(#names - shown)
	elseif shown > 1 then
		text = table.concat(names, ", ", 1, shown - 1) .. " and " .. names[shown]
	end
	return text
end

-- The guide's title and lines, or a function giving both when they depend on what the box is editing.
local function guide(owner, title, lines)
	owner:HookScript("OnEnter", function(self)
		local heading, list = title, lines
		if type(title) == "function" then heading, list = title() end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(heading, 1, 1, 1)
		for _, line in ipairs(list) do
			if type(line) == "table" then
				GameTooltip:AddLine(S.Hex(C.accent, line[1]) .. "  " .. line[2], 0.8, 0.8, 0.8, true)
			elseif line:sub(1, 1) == "#" then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine(line:sub(2), 1, 1, 1)
			else
				GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true)
			end
		end
		GameTooltip:Show()
	end)
	owner:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

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

-- An action dragged to a new place in the list; it becomes the selected one.
local function move(from, to)
	local rotation, state = RA.Window.Selected(), RA.Window.state
	local mode = rotation and currentMode(rotation, state)
	if mode and RA.Rotation.Move(mode.actions, from, to) then
		S.Dismiss()
		state.action = to
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
	S.Well(d)
	-- the controls sit inside the well's frame, however thick the theme draws it
	local pad = PAD + S.metrics.wellInset
	d.pad = pad
	local inner = width - 2 * pad

	d.title = S.Text(d, "normal")
	d.title:SetPoint("TOPLEFT", pad, -pad)
	d.title:SetWidth(inner)
	d.title:SetWordWrap(false)
	d.status = S.Text(d, "small", C.muted)
	d.status:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -4)
	d.status:SetWidth(inner)

	-- a readback that opens its sheet when clicked; hovering shows all of it (b.full) when it's too long to fit
	local function readback(lines, title, open)
		local b = CreateFrame("Button", nil, d)
		b:SetSize(inner, lines * 14)
		b.text = S.Text(b, "small")
		b.text:SetPoint("TOPLEFT")
		b.text:SetPoint("BOTTOMRIGHT")
		b.text:SetJustifyH("LEFT")
		b.text:SetJustifyV("TOP")
		b:SetScript("OnClick", open)
		b:SetScript("OnEnter", function(self)
			if self.full then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(title, 1, 1, 1)
				GameTooltip:AddLine(self.full, 0.8, 0.8, 0.8, true)
				GameTooltip:AddLine("Click to edit.", 0.5, 0.5, 0.5)
				GameTooltip:Show()
			end
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return b
	end
	d.whenLabel = label(d, "Conditions")
	d.whenReadback = readback(2, "Conditions", function() Editor.OpenConditions() end)
	d.editWhen = S.Button(d, "Edit Conditions", "secondary", 130, function() Editor.OpenConditions() end,
		"Where the spell is cast and when the game lets this line run: the target, modifier keys, stance and more.")
	d.triggerLabel = label(d, "Trigger")
	d.readback = readback(3, "Trigger", function() Editor.OpenTrigger() end)
	d.triggerRow = CreateFrame("Frame", nil, d)
	d.triggerRow:SetSize(inner, CONTROL_H)
	d.editTrigger = S.Button(d.triggerRow, "Edit Trigger", "secondary", 110, function() Editor.OpenTrigger() end,
		"Build the trigger from conditions, or type it.")
	d.editTrigger:SetPoint("LEFT")
	d.place = S.Dropdown(d.triggerRow, inner - 110 - GAP, function(value)
		edit(function(a) a.keep = value == "keep" or nil end)
	end)
	d.place:SetPoint("LEFT", d.editTrigger, "RIGHT", GAP, 0)
	d.place:SetOptions(PLACES)
	d.jumps = S.Text(d, "small", C.muted)
	d.jumps:SetWidth(inner)
	d.jumps:SetHeight(14)
	d.jumps:SetWordWrap(false)
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
		"Casts each spell once, then stops until the sequence resets (on a new target, after combat). Without Smart Picks, good for debuffs you keep up all fight; with it, a trigger like [nodebuff:X] recasts them when they fall off.",
		function(on) edit(function(a) a.once = on or nil end) end)
	d.offGcd = W.Toggle(d, "Off the Global Cooldown",
		"Runs on every press, alongside whatever casts: trinkets, racials, cooldowns that don't trigger the global cooldown, and next-swing attacks like Heroic Strike. With Smart Picks on, it runs after the main spell and follows its trigger, such as [power>=50] to keep rage for the rest.",
		function(on) edit(function(a) a.offGcd = on or nil end) end)
	d.moving = W.Toggle(d, "Cast While Moving",
		"Smart Picks passes over a spell with a cast time while you move. Turn this on for one you can cast on the move anyway, like Pyroblast with a [buff:Hot Streak] trigger.",
		function(on) edit(function(a) a.moving = on or nil end) end)
	d.textLabel = label(d, "Lines")
	d.text = S.TextArea(d, "RotationAssistActionText", inner, 110, { onInput = function(text)
		edit(function(a)
			if a.kind == "steps" then
				local steps = {}
				for line in text:gmatch("[^\n]+") do steps[#steps + 1] = line end
				a.steps = steps
			else
				a.text = text
			end
		end)
	end })

	d.remove = S.Button(d, "Remove", "danger", 70, remove)
	d.remove:SetPoint("BOTTOMRIGHT", -pad, pad)

	d.none = S.Text(d, "small", C.muted)
	d.none:SetPoint("TOPLEFT", pad, -pad)
	d.none:SetWidth(inner)
	d.none:SetText("Pick an action to change it.\n\nThe button tries actions from the top down on every press and casts the first one that's ready, so put what matters most first. Drag an action up or down the list to change its place.\n\nDrag spells here from your spellbook, or type a name above.")
	return d
end

-- Stacks the controls this kind of action uses under the title, top to bottom. placed: the spell has a trigger
-- whose When Met choice matters (not off the global cooldown).
local function layoutDetail(d, kind, placed)
	local controls = {
		{ d.whenLabel, d.whenReadback, d.editWhen, show = kind == "spell" or kind == "sequence" },
		{ d.triggerLabel, d.readback, d.triggerRow, show = kind == "spell" },
		{ d.jumps, show = kind == "spell" and placed },
		{ d.spellsLabel, d.spells, show = kind == "sequence" },
		{ d.resetLabel, d.reset, show = kind == "sequence" },
		{ d.once, show = kind == "sequence" },
		{ d.offGcd, show = kind == "spell" or kind == "macro" },
		{ d.moving, show = kind == "spell" },
		{ d.textLabel, d.text, show = kind == "steps" or kind == "macro" },
	}
	local y = d.pad + 16 + 4 + 12 + PAD
	for _, group in ipairs(controls) do
		for _, w in ipairs(group) do
			if group.show then
				w:ClearAllPoints()
				w:SetPoint("TOPLEFT", d.pad, -y)
				w:Show()
				y = y + (w.GetHeight and w:GetHeight() or 12) + 4
			else
				w:Hide()
			end
		end
		if group.show then y = y + GAP - 4 end
	end
end

-- The builder sheet ---------------------------------------------------------------------------------------------
-- Builds the selected action's trigger or conditions from rows: each group's rows must all hold. Changes are written
-- to the action as they're made; rows not filled in yet are left out of the text. Edit as Text swaps the rows for
-- the raw box. What differs between the two is in SHEETS below.

local MAX_TERMS = 8
local COL = { what = 176, has = 96, name = 150, op = 100, value = 48, remove = 28 }
local ROW_W = COL.what + COL.has + COL.name + COL.op + COL.value + COL.remove + 5 * GAP
local SHEET_W = ROW_W + 2 * PAD

-- A kind menu: each group's heading over its kinds, by their short names. The closed dropdown shows the full label,
-- so the menu's options go with a list of { value, text = label } for showing the choice.
local function options(terms)
	local menu, labels, group = {}, {}, nil
	for _, t in ipairs(terms) do
		if t.group ~= group then
			group = t.group
			menu[#menu + 1] = { heading = group }
		end
		menu[#menu + 1] = { value = t.kind, text = t.short or t.label }
		labels[#labels + 1] = { value = t.kind, text = t.label }
	end
	return menu, labels
end
local WHAT_MENU, WHAT_OPTIONS = options(RA.Triggers.TERMS)
local COND_MENU, COND_OPTIONS = options(RA.Conditions.TERMS)
local YES_OPTIONS = { { value = "has", text = "Yes" }, { value = "no", text = "No" } }
local HAS_OPTIONS = { { value = "has", text = "Has" }, { value = "no", text = "Missing" } }
local CAST_OPTIONS = { { value = "has", text = "Cast" }, { value = "no", text = "Not Cast" } }
local TIME_OPTIONS = {
	{ value = "", text = "Any Time" },
	{ value = "<", text = "Under" },
	{ value = "<=", text = "At Most" },
	{ value = ">", text = "Over" },
	{ value = ">=", text = "At Least" },
}
local COUNT_OPTIONS = {
	{ value = "<", text = "Fewer Than" },
	{ value = "<=", text = "At Most" },
	{ value = "=", text = "Exactly" },
	{ value = ">=", text = "At Least" },
	{ value = ">", text = "More Than" },
}
local VALUE_OPTIONS = {
	{ value = "<", text = "Under" },
	{ value = "<=", text = "At Most" },
	{ value = "=", text = "Exactly" },
	{ value = ">=", text = "At Least" },
	{ value = ">", text = "Over" },
}

local sheet

local function optionText(options, value)
	local text = options[1].text
	for _, o in ipairs(options) do
		if o.value == value then text = o.text end
	end
	return text
end

local function sheetAction()
	local rotation = RA.Window.Selected()
	local action = rotation and selectedAction(rotation, RA.Window.state)
	return action == sheet.action and action or nil
end

local function termCount()
	local n = 0
	for _, group in ipairs(sheet.groups) do n = n + #group end
	return n
end

local sheetRender

-- Writes the rows to the action's field.
local function commit()
	local action = sheetAction()
	if action then
		action[sheet.def.field] = sheet.def.write(sheet.groups)
		RA.Window.Edited()
	end
	sheetRender()
end

-- A blank trigger row of the kind the last row was, so a list of buffs is quick to fill in.
local function newTrigger(like)
	local kind = like and like.kind or "buff"
	local shape = RA.Triggers.SHAPES[kind]
	return { kind = kind, name = "", op = shape ~= "aura" and ">=" or nil }
end

-- A condition's arg when its kind is picked: a choice's first option, else empty.
local function firstArg(kind)
	local def = RA.Conditions.DEFS[kind]
	return def.arg == "choice" and def.choices[1].value or ""
end

-- A blank condition row: the last row's kind, except one that only makes sense once per group.
local function newCondition(like)
	local kind = like and like.kind or "harm"
	if kind == "unit" or kind == "always" then kind = "harm" end
	return { kind = kind, arg = firstArg(kind) }
end

local function newTerm(like)
	return sheet.def.newTerm(like)
end

-- Names for the aura picker: the auras on the player and the target now, the spellbook, and the names this rotation's
-- triggers already use, each once.
local function auraNames()
	local items, seen = {}, {}
	local function add(name, icon, source)
		local key = name and name:lower()
		if key and key ~= "" and not seen[key] then
			seen[key] = true
			items[#items + 1] = { value = name, text = name, icon = icon, tooltip = source }
		end
	end
	for _, unit in ipairs({ "player", "target" }) do
		for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
			for i = 1, 40 do
				local name, _, icon = UnitAura(unit, i, filter)
				if not name then break end
				add(name, icon, unit == "player" and "On you now." or "On your target now.")
			end
		end
	end
	local rotation = RA.Window.Selected()
	for _, mode in ipairs(rotation and rotation.modes or {}) do
		for _, a in ipairs(mode.actions) do
			for _, group in ipairs(RA.Triggers.Read(a.trigger) or {}) do
				for _, p in ipairs(group) do add(p.name, nil, "In this rotation's triggers.") end
			end
		end
	end
	local i = 1
	local name = GetSpellName and GetSpellName(i, BOOKTYPE_SPELL)
	while name do
		add(name, GetSpellTexture and GetSpellTexture(i, BOOKTYPE_SPELL), "In your spellbook.")
		i = i + 1
		name = GetSpellName(i, BOOKTYPE_SPELL)
	end
	return items
end

local function pickerSpec(term)
	local names = auraNames()
	return {
		placeholder = "Search, or Type Any Name",
		search = function(q)
			local typed, lower, items = RA.Spells.Trim(q), q:lower(), {}
			if typed ~= "" then items[1] = { value = typed, text = ("Use \"%s\""):format(typed), tooltip = "The name as typed, for an aura that isn't up now." } end
			for _, item in ipairs(names) do
				if #items < 200 and (lower == "" or item.text:lower():find(lower, 1, true)) then items[#items + 1] = item end
			end
			return items
		end,
		emptyText = "Type a Name",
		onPick = function(value)
			term.name = value
			commit()
		end,
	}
end

local function createRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(ROW_W, CONTROL_H)
	row.what = S.Dropdown(row, COL.what, function(kind)
		sheet.def.changeKind(row.term, kind)
		commit()
	end)
	row.has = S.Dropdown(row, COL.has, function(value)
		row.term.no = value == "no" or nil
		commit()
	end)
	row.choice = S.Dropdown(row, COL.name, function(value)
		row.term.arg = value
		commit()
	end)
	row.arg = S.Input(row, nil, COL.name, "", 60)
	row.arg:SetScript("OnTextChanged", function(self, userInput)
		self:UpdatePlaceholder()
		if userInput then
			row.term.arg = self:GetText()
			commit()
		end
	end)
	row.name = S.PickerButton(row, COL.name, function() return pickerSpec(row.term) end)
	row.op = S.Dropdown(row, COL.op, function(value)
		row.term.op = value ~= "" and value or nil
		if not row.term.op then row.term.value = nil end
		commit()
	end)
	row.value = S.Input(row, nil, COL.value, "#", 6)
	row.value:SetScript("OnTextChanged", function(self, userInput)
		self:UpdatePlaceholder()
		if userInput then
			row.term.value = tonumber(self:GetText())
			commit()
		end
	end)
	row.remove = S.Button(row, "X", "secondary", COL.remove, function()
		local group = sheet.groups[row.group]
		table.remove(group, row.index)
		if #group == 0 then table.remove(sheet.groups, row.group) end
		commit()
	end, "Remove this condition.")
	return row
end

local function setInput(input, text)
	if not input.focused then
		input:SetText(text or "")
		input:UpdatePlaceholder()
	end
end

-- A trigger row's controls: what, has or missing, the name, a comparison and its number.
local function fillTrigger(row, term)
	local shape = RA.Triggers.SHAPES[term.kind]
	row.what:SetOptions(WHAT_MENU)
	row.what:SetText(optionText(WHAT_OPTIONS, term.kind))
	local hasOptions = term.kind == "cast" and CAST_OPTIONS or HAS_OPTIONS
	row.has:SetOptions(hasOptions)
	row.has:SetText(optionText(hasOptions, term.no and "no" or "has"))
	row.name:SetText(RA.Spells.Trim(term.name) ~= "" and term.name or S.Hex(C.muted, "Pick a Name"))
	local opOptions = shape == "aura" and TIME_OPTIONS or shape == "count" and COUNT_OPTIONS or VALUE_OPTIONS
	row.op:SetOptions(opOptions)
	row.op:SetText(optionText(opOptions, term.op or ""))
	setInput(row.value, term.value and tostring(term.value) or "")
	return {
		{ row.what, true },
		{ row.has, shape == "aura" },
		{ row.name, shape ~= "value", true },
		{ row.op, true },
		{ row.value, term.op ~= nil },
	}
end

-- A condition row's controls: what, yes or no, and its choice or typed text.
local function fillCondition(row, term)
	local def = RA.Conditions.DEFS[term.kind]
	row.what:SetOptions(COND_MENU)
	row.what:SetText(optionText(COND_OPTIONS, term.kind))
	row.has:SetOptions(YES_OPTIONS)
	row.has:SetText(optionText(YES_OPTIONS, term.no and "no" or "has"))
	if def.arg == "choice" then
		local arg = term.kind == "unit" and RA.Conditions.Unit(term.arg) or (term.arg or ""):lower()
		local listed = false
		for _, c in ipairs(def.choices) do listed = listed or c.value == arg end
		row.choice:SetOptions(def.choices)
		row.choice:SetText(listed and optionText(def.choices, arg) or term.arg)
	end
	row.arg.placeholder:SetText(def.placeholder or "")
	setInput(row.arg, term.arg)
	local typed = def.arg == "text" or def.arg == "required"
	return {
		{ row.what, true },
		{ row.has, not def.fixed },
		{ row.choice, def.arg == "choice", true },
		{ row.arg, typed, true },
	}
end

-- Lays a row's controls left to right, showing only the ones its kind of term uses.
local function fillRow(row, term)
	row.term = term
	local controls = sheet.def.fill(row, term)
	local shown = {}
	-- the name (or a condition's argument) takes whatever the shown controls and the remove button leave
	local spare = ROW_W - COL.remove - GAP
	for _, c in ipairs(controls) do
		shown[c[1]] = c[2]
		if c[2] and not c[3] then spare = spare - c[1]:GetWidth() - GAP end
	end
	for _, c in ipairs(controls) do
		if c[3] then
			c[1]:SetWidth(spare)
			if c[1].menu then c[1].menu:SetWidth(spare) end
		end
	end
	for _, w in ipairs({ row.what, row.has, row.name, row.op, row.value, row.choice, row.arg }) do
		if not shown[w] then w:Hide() end
	end
	local x = 0
	for _, c in ipairs(controls) do
		c[1]:ClearAllPoints()
		if c[2] then
			c[1]:SetPoint("LEFT", row, "LEFT", x, 0)
			c[1]:Show()
			x = x + c[1]:GetWidth() + GAP
		else
			c[1]:Hide()
		end
	end
	row.remove:ClearAllPoints()
	row.remove:SetPoint("RIGHT")
end

-- What the two sheets differ in: the action field they edit, how they read, write and say it, their rows, and
-- their words.
local SHEETS = {
	trigger = {
		field = "trigger",
		title = "Trigger for %s",
		intro = "Rotation Assist checks these as you press. While they hold and the spell is ready, the spell can be picked.",
		orHeading = "Or All of These",
		orTip = "Add a group of conditions that will do instead of the ones above.",
		placeholder = "None, or Like [buff:Clearcasting]",
		guide = { "Trigger", TRIGGER_GUIDE },
		empty = "Nothing yet: the spell is tried on every press.",
		clearTip = "Remove the trigger: the spell is tried in its place on every press.",
		read = RA.Triggers.Read, write = RA.Triggers.Write, describe = RA.Triggers.Describe,
		complete = RA.Triggers.Complete, problems = RA.Triggers.Problems,
		newTerm = newTrigger, fill = fillTrigger,
		changeKind = function(term, kind)
			local shape, was = RA.Triggers.SHAPES[kind], RA.Triggers.SHAPES[term.kind]
			term.kind = kind
			if shape ~= was then
				term.op, term.value = shape ~= "aura" and ">=" or nil, nil
				if shape == "value" then term.name = nil else term.name = term.name or "" end
			end
		end,
	},
	conditions = {
		field = "when",
		title = "Conditions for %s",
		intro = "The game checks these as you press. The first group that holds runs the line, on its unit; when none holds, the line is skipped.",
		orHeading = "Otherwise, All of These",
		orTip = "Add a group the game tries when the ones above don't hold, such as one that casts on you instead.",
		placeholder = "Always, or Like [harm] or [mod:shift]",
		guide = { "Conditions", CONDITIONS_GUIDE },
		empty = "None: the line always runs, on your target.",
		clearTip = "Remove the conditions: the line always runs, on your target.",
		read = RA.Conditions.Read, write = RA.Conditions.Write, describe = RA.Conditions.Describe,
		complete = RA.Conditions.Complete, problems = function() return {} end,
		newTerm = newCondition, fill = fillCondition,
		changeKind = function(term, kind)
			if kind ~= term.kind then
				term.kind, term.key, term.arg = kind, nil, firstArg(kind)
				if RA.Conditions.DEFS[kind].fixed then term.no = nil end
			end
		end,
	},
}

local function setTextMode(on)
	if on then
		local action = sheetAction()
		sheet.text:SetText(action and action[sheet.def.field] or "")
		sheet.text:UpdatePlaceholder()
	else
		local groups, problem = sheet.def.read(sheet.text:GetText())
		local count = 0
		for _, group in ipairs(groups or {}) do count = count + #group end
		if groups and count <= MAX_TERMS then
			sheet.groups = groups
			sheet.problem = nil
		else
			on = true
			sheet.problem = problem or ("More Than %d Conditions: Keep It as Text"):format(MAX_TERMS)
		end
	end
	sheet.textMode = on
	sheetRender()
end

local function createSheet()
	local pad = S.metrics.inset
	S.RefreshFonts()
	local f = CreateFrame("Frame", "RotationAssistTriggerFrame", UIParent)
	f:SetWidth(SHEET_W + 2 * (pad - PAD))
	f:SetPoint("TOP", UIParent, "TOP", 0, -140)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- a named frame moved by hand is saved in layout-local.txt and put back there at login
		self:SetUserPlaced(false)
	end)
	RA.PixelScale(f)
	S.Frame(f, "popup")
	tinsert(UISpecialFrames, "RotationAssistTriggerFrame")
	f:SetScript("OnHide", function()
		S.CloseMenus()
		S.Picker.Close()
		f.text:ClearFocus()
	end)
	f.pad = pad

	f.title = S.Text(f, "large")
	-- centered on the Edit as Text button beside it, so the two read as one header row
	f.title:SetPoint("LEFT", f, "TOPLEFT", pad, -(pad + CONTROL_H / 2))
	f.title:SetWidth(ROW_W - 130)
	f.title:SetWordWrap(false)
	f.mode = S.Button(f, "Edit as Text", "secondary", 120, function() setTextMode(not f.textMode) end,
		"Switch between the rows and the text they make.")
	f.mode:SetPoint("TOPRIGHT", -pad, -pad)
	f.intro = S.Text(f, "small", C.muted)
	f.intro:SetWidth(ROW_W)
	f.intro:SetJustifyH("LEFT")

	f.rows, f.headings, f.ands = {}, {}, {}
	f.orButton = S.Button(f, "Or", "secondary", 80, function()
		local last = f.groups[#f.groups]
		f.groups[#f.groups + 1] = { newTerm(last and last[#last]) }
		sheetRender()
	end)
	f.orButton:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(f.def.orTip, nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	f.orButton:HookScript("OnLeave", function() GameTooltip:Hide() end)

	f.text = S.Input(f, "RotationAssistSheetText", ROW_W, "", 255, 4)
	f.text:SetScript("OnTextChanged", function(self, userInput)
		self:UpdatePlaceholder()
		local action = userInput and sheetAction()
		if action then
			action[f.def.field] = self:GetText()
			RA.Window.Edited()
			f.problem = nil
			sheetRender()
		end
	end)
	guide(f.text, function() return f.def.guide[1], f.def.guide[2] end)

	f.readLabel = label(f, "Reads As")
	f.readback = S.Text(f, "small")
	f.readback:SetWidth(ROW_W)
	f.readback:SetJustifyH("LEFT")
	f.readback:SetJustifyV("TOP")

	f.note = S.Text(f, "small", C.muted)
	f.note:SetWidth(ROW_W - 2 * (90 + GAP))
	f.note:SetJustifyH("LEFT")
	f.done = S.Button(f, "Done", "primary", 90, function() f:Hide() end)
	f.clear = S.Button(f, "Clear", "danger", 90, function()
		f.groups = {}
		f.text:SetText("")
		commit()
	end)
	f.clear:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(f.def.clearTip, nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	f.clear:HookScript("OnLeave", function() GameTooltip:Hide() end)
	f.done:SetPoint("BOTTOMRIGHT", -pad, pad)
	f.clear:SetPoint("RIGHT", f.done, "LEFT", -GAP, 0)
	S.OnDismiss(function() f:Hide() end)
	return f
end

-- Places everything top to bottom and sizes the sheet to fit.
sheetRender = function()
	local f, pad = sheet, sheet.pad
	local action = sheetAction()
	local y = pad
	local function place(region, h, x)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", f, "TOPLEFT", pad + (x or 0), -y)
		region:Show()
		y = y + h
	end
	local def = f.def
	f.title:SetText(def.title:format(action and RA.Rotation.ActionText(action) or "?"))
	y = y + CONTROL_H + GAP
	f.intro:SetText(def.intro)
	place(f.intro, 2 * 14)
	y = y + PAD
	f.text.placeholder:SetText(def.placeholder)
	f.mode.label:SetText(f.textMode and "Edit as Conditions" or "Edit as Text")

	local used, full = 0, termCount() >= MAX_TERMS
	for gi, group in ipairs(f.textMode and {} or f.groups) do
		local heading = f.headings[gi] or W.Heading(f, "")
		f.headings[gi] = heading
		heading:SetText(gi == 1 and "All of These" or def.orHeading)
		place(heading, 14 + 4)
		for ti, term in ipairs(group) do
			used = used + 1
			local row = f.rows[used] or createRow(f)
			f.rows[used] = row
			row.group, row.index = gi, ti
			fillRow(row, term)
			place(row, CONTROL_H + 4)
		end
		local andButton = f.ands[gi] or S.Button(f, "And", "secondary", 80, function()
			local g = f.groups[gi]
			g[#g + 1] = newTerm(g[#g])
			sheetRender()
		end, "Add a condition that must hold as well.")
		f.ands[gi] = andButton
		if full then andButton:Disable() else andButton:Enable() end
		place(andButton, CONTROL_H + GAP)
	end
	for i = used + 1, #f.rows do f.rows[i]:Hide() end
	for i = (f.textMode and 0 or #f.groups) + 1, #f.headings do
		f.headings[i]:Hide()
		f.ands[i]:Hide()
	end
	if f.textMode then
		f.orButton:Hide()
		place(f.text, f.text.box:GetHeight() + GAP)
		f.text:Show()
	else
		f.text:Hide()
		if full then f.orButton:Disable() else f.orButton:Enable() end
		f.orButton.label:SetText(#f.groups == 0 and "Add" or "Or")
		place(f.orButton, CONTROL_H + PAD)
	end

	local text = RA.Spells.Trim(action and action[def.field])
	local said = text ~= "" and def.describe(text) or nil
	local lines = said and select(2, said:gsub("\n", "\n")) + 1 or 1
	place(f.readLabel, 12 + 4)
	f.readback:SetText(said or S.Hex(C.muted, text ~= "" and "It can't be read back as it is; fix it as text." or def.empty))
	f.readback:SetHeight(lines * 14)
	place(f.readback, lines * 14 + PAD)

	local problems = def.problems(text)
	local incomplete = 0
	for _, group in ipairs(f.textMode and {} or f.groups) do
		for _, p in ipairs(group) do
			if not def.complete(p) then incomplete = incomplete + 1 end
		end
	end
	local note = f.problem or problems[1]
	f.note:SetText(note and S.Hex(C.warn, note)
		or incomplete > 0 and S.Count(incomplete, "Condition") .. " Not Filled In Yet"
		or full and not f.textMode and ("At Most %d Conditions Here; Edit as Text for More"):format(MAX_TERMS) or "")
	f.note:ClearAllPoints()
	f.note:SetPoint("LEFT", f, "BOTTOMLEFT", pad, pad + CONTROL_H / 2)
	f:SetHeight(y + CONTROL_H + pad)
end

-- Opens a sheet on the selected action. What the rows can't show opens as text.
local function openSheet(key, kinds)
	local rotation = RA.Window.Selected()
	local action = rotation and selectedAction(rotation, RA.Window.state)
	if action and kinds[action.kind] then
		S.CloseMenus()
		sheet = sheet or createSheet()
		sheet.def = SHEETS[key]
		sheet.key = key
		sheet.action = action
		local groups, problem = sheet.def.read(action[sheet.def.field])
		sheet.groups = groups or {}
		sheet.textMode = groups == nil or termCount() > MAX_TERMS
		sheet.problem = problem
		if sheet.textMode then sheet.text:SetText(action[sheet.def.field] or "") end
		sheetRender()
		sheet:Show()
		sheet:Raise()
	end
end

function Editor.OpenTrigger()
	openSheet("trigger", { spell = true })
end

function Editor.OpenConditions()
	openSheet("conditions", { spell = true, sequence = true })
end

function Editor.Sheet()
	return sheet
end
Editor.TriggerSheet = Editor.Sheet

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
	S.Well(well)
	-- the rows sit inside the well's frame, however thick the theme draws it
	local wi = 1 + S.metrics.wellInset
	f.list = S.List.New(well, "RotationAssistActionList", LIST_W - 14 - 2 * (wi - 1), listH - 2 * wi, "content", 14)
	f.list.scroll:SetPoint("TOPLEFT", wi, -wi)
	f.list:SetReorder(move)
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
	if action.kind == "spell" and RA.Triggers.Has(action.trigger) then parts[#parts + 1] = "Trigger " .. RA.Spells.Trim(action.trigger) end
	if action.kind == "spell" and action.keep then parts[#parts + 1] = "Stays in Place" end
	if action.offGcd then parts[#parts + 1] = "Off-GCD" end
	if action.kind == "spell" and action.moving then parts[#parts + 1] = "While Moving" end
	return #parts > 0 and table.concat(parts, "  ") or nil
end

local function renderDetail(rotation, state, compiled)
	local d = frame.detail
	local action, mode = selectedAction(rotation, state)
	local controls = { d.title, d.status, d.remove }
	for _, w in ipairs(controls) do if action then w:Show() else w:Hide() end end
	if action then
		d.none:Hide()
		local triggered = action.kind == "spell" and RA.Triggers.Has(action.trigger)
		local placed = triggered and not action.offGcd
		layoutDetail(d, action.kind, placed)
		d.readback.text:SetText(triggered and (RA.Triggers.Describe(action.trigger, true) or S.Hex(C.accent, RA.Spells.Trim(action.trigger)))
			or S.Hex(C.muted, "None: the spell is tried in its place on every press."))
		d.readback.full = triggered and (RA.Triggers.Describe(action.trigger) or RA.Spells.Trim(action.trigger)) or nil
		d.editTrigger.label:SetText(triggered and "Edit Trigger" or "Add Trigger")
		if placed then d.place:Show() else d.place:Hide() end
		d.place:SetText(PLACES[action.keep and 2 or 1].text)
		local jumps = Editor.JumpsAhead(mode.actions, state.action)
		d.jumps:SetText(action.keep and "While met, it's tried in its place in the list."
			or #jumps == 0 and "While met, it's tried first."
			or ("While met, it goes ahead of %s."):format(S.Hex(C.text, Editor.NameList(jumps))))
		d.title:SetText(RA.Rotation.ActionText(action))
		local status = compiled.status[state.action]
		local kindText = ({ spell = "Spell", sequence = "Sequence", steps = "Steps", macro = "Macro" })[action.kind]
		local problems = action.kind == "spell" and RA.Triggers.Problems(action.trigger) or {}
		d.status:SetText(("%s %d of %d"):format(kindText, state.action, #mode.actions) .. (status == "skipped"
			and ("  " .. S.Hex(C.bad, "Skipped: Not Known on This Character")) or status == "partial"
			and ("  " .. S.Hex(C.warn, "Some Spells Not Known")) or "")
			.. (#problems > 0 and ("  " .. S.Hex(C.warn, problems[1])) or ""))
		local when = RA.Spells.Trim(action.when)
		d.whenReadback.text:SetText(when == "" and S.Hex(C.muted, "None: the line always runs, on your target.")
			or RA.Conditions.Describe(when, true) or S.Hex(C.accent, when))
		d.whenReadback.full = when ~= "" and (RA.Conditions.Describe(when) or when) or nil
		setText(d.spells, RA.Spells.ListText(action.spells))
		setText(d.reset, action.reset)
		d.offGcd:SetChecked(action.offGcd)
		d.moving:SetChecked(action.moving)
		d.once:SetChecked(action.once)
		d.text:SetValue(action.kind == "steps" and table.concat(action.steps or {}, "\n") or action.text)
		d.textLabel:SetText(action.kind == "steps" and "Steps, One per Line (a Spell Name or a Macro Line)" or "Lines")
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
			move = i, dragLabel = RA.Rotation.ActionText(action),
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
