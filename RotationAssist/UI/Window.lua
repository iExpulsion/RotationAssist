local _, NS = ...
local RA = NS.RA

-- The rotation window: a searchable rotation sidebar on the left and the
-- selected rotation on the right (header with the main actions, tabs, the tab's content and a footer).
local Window = {}
RA.Window = Window

local S = RA.Style
local C = S.colors

local W, H = 780, 560
local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H
local TITLE_H, SIDEBAR_W, TABS_H = 36, 240, 32
local HEADER_H = PAD + CONTROL_H + GAP + CONTROL_H + GAP
local FOOTER_H = PAD + CONTROL_H + PAD
Window.BODY_W = W - SIDEBAR_W - 2 * PAD
Window.BODY_H = H - TITLE_H - HEADER_H - TABS_H - PAD - FOOTER_H - PAD
local TABS = {
	{ key = "actions", label = "Actions" },
	{ key = "modes", label = "Modes" },
	{ key = "keys", label = "Keys" },
	{ key = "preview", label = "Preview" },
	{ key = "notes", label = "Notes" },
}
local EDITORS = { actions = "ActionEditor", modes = "ModeEditor", keys = "KeysEditor", preview = "PreviewEditor" }
local SPECS_KEY = "\1specs"

local frame
local state = { selected = nil, tab = "actions", mode = 1, action = nil, collapsed = {}, search = "" }
Window.state = state

local function setShown(f, shown)
	if shown then f:Show() else f:Hide() end
end

function Window.Selected()
	return state.selected and RA.db.rotations[state.selected]
end

function Window.Select(name)
	S.Dismiss()
	state.selected = name
	state.mode, state.action, state.message = 1, nil, nil
	Window.Render()
end

-- Sidebar --------------------------------------------------------------------------------------------------

local function matches(rotation)
	local q = state.search
	return q == "" or rotation.name:lower():find(q, 1, true) ~= nil
end

local function linkedSpecs()
	local rows, links = {}, RA:Links()
	for g = 1, RA:SpecCount() do
		local rotation = links[g] and RA.db.rotations[links[g]]
		if rotation and matches(rotation) then rows[#rows + 1] = { group = g, rotation = rotation } end
	end
	return rows
end

local function groupedRotations()
	local groups, byKey = {}, {}
	for _, rotation in pairs(RA.db.rotations) do
		if matches(rotation) and #RA:LinkedSpecs(rotation.name) == 0 then
			local key = table.concat(rotation.classes or {}, "/")
			local group = byKey[key]
			if not group then
				group = { key = key, classes = rotation.classes or {}, fits = RA:Fits(rotation), rotations = {} }
				byKey[key] = group
				groups[#groups + 1] = group
			end
			table.insert(group.rotations, rotation)
		end
	end
	for _, group in ipairs(groups) do
		table.sort(group.rotations, function(a, b) return a.name:lower() < b.name:lower() end)
	end
	table.sort(groups, function(a, b)
		if a.fits ~= b.fits then return a.fits end
		return a.key < b.key
	end)
	return groups
end

local function renderSidebar()
	local list = frame.list
	local first, firstFit = nil, nil
	list:Begin()

	local specs = linkedSpecs()
	if #specs > 0 then
		local collapsed = state.collapsed[SPECS_KEY] == true and state.search == ""
		list:Add({
			text = "Your Specs", header = true, collapsed = collapsed, status = S.Hex(C.muted, #specs),
			onClick = function()
				state.collapsed[SPECS_KEY] = not collapsed
				Window.Render()
			end,
			tooltip = function(tt)
				tt:AddLine("Your Specs", 1, 1, 1)
				tt:AddLine("Rotations linked to this character's talent specs. The active spec's rotation is the one the button runs.", 0.8, 0.8, 0.8, true)
			end,
		})
		for _, row in ipairs(specs) do
			local rotation, active = row.rotation, row.group == RA:ActiveGroup()
			if active or not firstFit then firstFit = rotation end
			first = first or rotation
			if not collapsed then
				list:Add({
					text = S.Hex(active and C.good or C.muted, row.group) .. "   " .. rotation.name,
					status = active and S.Hex(C.good, "Active") or nil,
					indent = 12,
					selected = rotation.name == state.selected,
					onClick = function() Window.Select(rotation.name) end,
				})
			end
		end
	end

	local groups = groupedRotations()
	local nested = #specs > 0 and #groups > 0
	if nested then
		local saved = 0
		for _, group in ipairs(groups) do saved = saved + #group.rotations end
		list:Add({ text = "Saved Rotations", header = true, indent = 16, status = S.Hex(C.muted, saved) })
	end
	for _, group in ipairs(groups) do
		local c = state.collapsed[group.key]
		if c == nil then c = not group.fits end
		local collapsed = c and state.search == ""
		list:Add({
			text = group.key == "" and "No Class" or RA:ClassText(group.classes),
			status = S.Hex(C.muted, #group.rotations),
			header = true, collapsed = collapsed, indent = nested and 12 or 0,
			onClick = function()
				state.collapsed[group.key] = not collapsed
				Window.Render()
			end,
		})
		for _, rotation in ipairs(group.rotations) do
			first = first or rotation
			if group.fits then firstFit = firstFit or rotation end
			if not collapsed then
				list:Add({
					text = rotation.name,
					indent = nested and 24 or 12,
					selected = rotation.name == state.selected,
					onClick = function() Window.Select(rotation.name) end,
				})
			end
		end
	end
	list:End()

	if not Window.Selected() then
		local pick = firstFit or first
		state.selected = pick and pick.name or nil
	end
	setShown(frame.noMatches, state.search ~= "" and first == nil)
end

-- Main pane ------------------------------------------------------------------------------------------------

local function renderStatus()
	local text, color
	if InCombatLockdown() and RA.Engine.pending then
		text, color = "Changes Apply After Combat", C.warn
	elseif InCombatLockdown() then
		text, color = "Locked in Combat", C.warn
	elseif RA.Engine.rotation then
		text, color = "Running " .. RA.Engine.rotation.name, C.good
	else
		text, color = "No Rotation for This Spec", C.muted
	end
	frame.statusDot:SetVertexColor(unpack(color))
	frame.statusText:SetText(text)
	frame.statusText:SetTextColor(unpack(color))
end

local function renderTabs()
	for i, tab in ipairs(TABS) do
		local b = frame.tabs[i]
		local selected = tab.key == state.tab
		b.label:SetTextColor(unpack(selected and C.text or C.muted))
		setShown(b.underline, selected)
		b:SetWidth(PAD + b.label:GetStringWidth() + PAD)
	end
	setShown(frame.notes, state.tab == "notes")
	for key, editor in pairs(frame.editors) do setShown(editor, key == state.tab) end
end

local function renderHeader(rotation)
	frame.name.committed = rotation.name
	if not frame.name.focused then frame.name:SetText(rotation.name) end
	frame.classes:SetText(RA:ClassText(rotation.classes))

	local count = RA:SpecCount()
	local groups = RA:LinkedSpecs(rotation.name)
	local options = { { value = 0, text = "Not Linked", tooltip = "Don't tie this rotation to a spec on this character." } }
	for g = 1, count do
		local other = RA:Links()[g]
		local tip = other and other ~= rotation.name and ("Linked to " .. other .. " now; picking it moves that link here.") or nil
		options[#options + 1] = { value = g, text = RA:SpecName(g) .. (g == RA:ActiveGroup() and " (Active)" or ""), tooltip = tip }
	end
	frame.specLink:SetOptions(options)
	local label = #groups == 0 and "Not Linked" or RA:SpecName(groups[1])
	if #groups > 1 then label = label .. (" +%d"):format(#groups - 1) end
	frame.specLink:SetText(label)

	local inUse = RA.Engine.rotation == rotation
	frame.use:SetLabel(inUse and "In Use" or "Use Rotation")
	if inUse then frame.use:Disable() else frame.use:Enable() end
	frame.use.tooltipText = inUse and "The rotation button is running this rotation." or
		("Link this rotation to your active spec (%s) and put it on the rotation button."):format(RA:SpecName(RA:ActiveGroup()))
end

local function renderRotation(rotation)
	renderHeader(rotation)
	renderTabs()
	local summary
	if state.tab == "notes" then
		frame.notes:SetValue(rotation.notes or "")
		summary = S.Hex(C.muted, "Saved as You Type")
	else
		summary = RA[EDITORS[state.tab]].Render(rotation, state)
	end
	frame.summary:SetText(state.message or summary or "")
end

function Window.Render()
	if frame and frame:IsShown() then
		frame.dirty = false
		renderSidebar()
		renderStatus()
		local rotation = Window.Selected()
		if rotation then frame.export:Enable() else frame.export:Disable() end
		setShown(frame.main, rotation ~= nil)
		setShown(frame.empty, rotation == nil)
		if rotation then renderRotation(rotation) end
	end
end

-- Coalesces bursts of events into one render on the next frame.
function Window.Refresh()
	if frame then frame.dirty = true end
end

function Window.Message(text)
	state.message = text
	Window.Render()
end

-- Saves an edit to the selected rotation: the button is rebuilt and the window redraws.
function Window.Edited()
	RA:Changed()
	Window.Render()
end

-- Construction ---------------------------------------------------------------------------------------------

local function newRotation()
	RA.Dialogs.ShowNew(function(name, template)
		local rotation = template and RA.Rotation.FromTemplate(template, name) or RA.Rotation.New(name)
		RA.Rotation.Add(rotation)
		state.search = ""
		frame.search:SetText("")
		state.collapsed[table.concat(rotation.classes, "/")] = false
		Window.Select(rotation.name)
	end)
end

local function useRotation()
	local rotation = Window.Selected()
	if rotation then
		RA:LinkSpec(rotation.name, RA:ActiveGroup())
		Window.Message(S.Hex(C.good, InCombatLockdown() and "In Use After Combat" or "In Use on the Rotation Button"))
	end
end

local function createTitleBar(f)
	local bar = CreateFrame("Frame", nil, f)
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("TOPRIGHT")
	bar:SetHeight(TITLE_H)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function()
		S.Dismiss()
		f:StartMoving()
	end)
	bar:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		local point, _, relPoint, x, y = f:GetPoint()
		RA.db.window = { point = point, relPoint = relPoint, x = x, y = y }
	end)
	S.Rule(bar, "BOTTOM")

	local title = S.Text(bar, "normal")
	title:SetPoint("LEFT", PAD, 0)
	title:SetText("Rotation " .. S.Hex(C.accent, "Assist"))
	local version = S.Text(bar, "small", C.muted)
	version:SetPoint("LEFT", title, "RIGHT", GAP, 0)
	version:SetText("v" .. RA.version)

	local inset = (TITLE_H - CONTROL_H) / 2
	local close = S.Button(bar, "Close", "ghost", 56, function() f:Hide() end)
	close:SetPoint("RIGHT", -inset, 0)
	f.statusText = S.Text(bar, "small", C.muted)
	f.statusText:SetPoint("RIGHT", close, "LEFT", -GAP, 0)
	f.statusDot = S.Solid(bar, "ARTWORK", C.muted)
	f.statusDot:SetSize(8, 8)
	f.statusDot:SetPoint("RIGHT", f.statusText, "LEFT", -GAP, 0)
end

local function createSidebar(f)
	local side = CreateFrame("Frame", nil, f)
	side:SetPoint("TOPLEFT", 0, -TITLE_H)
	side:SetPoint("BOTTOMLEFT")
	side:SetWidth(SIDEBAR_W)
	local fill = S.Solid(side, "BACKGROUND", C.sidebar)
	fill:SetPoint("TOPLEFT", 1, 0)
	fill:SetPoint("BOTTOMRIGHT", 0, 1)
	local edge = S.Solid(side, "BORDER", C.border)
	edge:SetWidth(1)
	edge:SetPoint("TOPRIGHT")
	edge:SetPoint("BOTTOMRIGHT")

	f.search = S.Input(side, "RotationAssistSearch", SIDEBAR_W - 2 * PAD, "Search Rotations", 40)
	f.search:SetPoint("TOPLEFT", PAD, -PAD)
	f.search:HookScript("OnTextChanged", function(self)
		state.search = self:GetText():lower()
		Window.Render()
	end)

	local listTop = PAD + CONTROL_H + GAP
	f.list = RA.List.New(side, "RotationAssistListScroll", SIDEBAR_W - 14, H - TITLE_H - listTop - FOOTER_H, "sidebar")
	f.list.scroll:SetPoint("TOPLEFT", 0, -listTop)
	f.noMatches = S.Text(side, "small", C.muted)
	f.noMatches:SetPoint("TOP", 0, -(listTop + PAD))
	f.noMatches:SetText("No rotations match your search.")

	local footer = CreateFrame("Frame", nil, side)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(FOOTER_H)
	S.Rule(footer, "TOP")
	local new = S.Button(footer, "New Rotation", "secondary", 100, newRotation,
		"Start a blank rotation for your classes, or start from an example.")
	new:SetPoint("LEFT", PAD, 0)
	f.export = S.Button(footer, "Export", "secondary", 50, function()
		local rotation = Window.Selected()
		if rotation then RA.Dialogs.ShowExport(rotation) end
	end, "Get the selected rotation as a string to share.")
	f.export:SetPoint("RIGHT", -PAD, 0)
	f.import = S.Button(footer, "Import", "secondary", 50, function()
		RA.Dialogs.ShowImport(function(rotation)
			RA.Rotation.Add(rotation)
			state.search = ""
			frame.search:SetText("")
			state.collapsed[table.concat(rotation.classes, "/")] = false
			Window.Select(rotation.name)
			Window.Message(S.Hex(C.good, "Imported as " .. rotation.name))
		end)
	end, "Add a rotation from a string someone shared.")
	f.import:SetPoint("RIGHT", f.export, "LEFT", -GAP, 0)
end

local function createHeader(main)
	local f = frame
	local row1 = CreateFrame("Frame", nil, main)
	row1:SetPoint("TOPLEFT", PAD, -PAD)
	row1:SetPoint("TOPRIGHT", -PAD, -PAD)
	row1:SetHeight(CONTROL_H)
	local row2 = CreateFrame("Frame", nil, main)
	row2:SetPoint("TOPLEFT", row1, "BOTTOMLEFT", 0, -GAP)
	row2:SetPoint("TOPRIGHT", row1, "BOTTOMRIGHT", 0, -GAP)
	row2:SetHeight(CONTROL_H)

	f.name = CreateFrame("EditBox", "RotationAssistNameBox", main)
	f.name:SetSize(260, CONTROL_H)
	f.name:SetAutoFocus(false)
	f.name:SetMaxLetters(40)
	S.SetFont(f.name, "large")
	f.name:SetTextInsets(GAP, GAP, 0, 0)
	f.name:SetPoint("LEFT", row1, "LEFT", -GAP, 0)
	S.Panel(f.name, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
	f.name:SetScript("OnEditFocusGained", function(self)
		self.focused = true
		self:SetBackdropColor(unpack(C.well))
		self:SetBackdropBorderColor(unpack(C.accent))
	end)
	f.name:SetScript("OnEditFocusLost", function(self)
		self.focused = false
		self:SetText(self.committed or "")
		self:SetBackdropColor(0, 0, 0, 0)
		self:SetBackdropBorderColor(0, 0, 0, 0)
	end)
	f.name:SetScript("OnEnter", function(self)
		if not self.focused then self:SetBackdropBorderColor(unpack(C.border)) end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Click to rename, then press Enter.")
		GameTooltip:Show()
	end)
	f.name:SetScript("OnLeave", function(self)
		if not self.focused then self:SetBackdropBorderColor(0, 0, 0, 0) end
		GameTooltip:Hide()
	end)
	f.name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	f.name:SetScript("OnEnterPressed", function(self)
		local rotation = Window.Selected()
		local newName = RA.Spells.Trim(self:GetText())
		if rotation and RA.Rotation.Rename(rotation, newName) then
			state.selected = newName
			self.committed = newName
		end
		self:ClearFocus()
		Window.Render()
	end)
	S.TrackInput(f.name)

	f.classes = S.Text(main, "small")
	f.classes:SetPoint("LEFT", row2, "LEFT", 0, 0)

	f.specLink = S.Dropdown(main, 150, function(group)
		local rotation = Window.Selected()
		if rotation then RA:LinkSpec(rotation.name, group ~= 0 and group or nil) end
		Window.Render()
	end)
	f.specLink:SetPoint("RIGHT", row2, "RIGHT", 0, 0)
	f.specLink.tooltipText = "The talent spec on this character that runs this rotation."
	local linkLabel = S.Text(main, "small", C.muted)
	linkLabel:SetPoint("RIGHT", f.specLink, "LEFT", -GAP, 0)
	linkLabel:SetText("Linked to")

	f.use = S.Button(main, "Use Rotation", "primary", 110, useRotation)
	f.use:SetPoint("RIGHT", row1, "RIGHT", 0, 0)
	f.duplicate = S.Button(main, "Duplicate", "secondary", 80, function()
		local rotation = Window.Selected()
		if rotation then Window.Select(RA.Rotation.Duplicate(rotation).name) end
	end, "Make a copy of this rotation to try changes on. The copy isn't linked to a spec.")
	f.duplicate:SetPoint("RIGHT", f.use, "LEFT", -GAP, 0)
	f.delete = S.Button(main, "Delete", "danger", 70, function()
		local rotation = Window.Selected()
		if rotation then
			RA.Dialogs.Confirm("RA_DELETE", rotation.name, function()
				RA.Rotation.Delete(rotation)
				Window.Select(nil)
			end)
		end
	end)
	f.delete:SetPoint("RIGHT", f.duplicate, "LEFT", -GAP, 0)
end

local function createTabBar(main)
	local f = frame
	local bar = CreateFrame("Frame", nil, main)
	bar:SetPoint("TOPLEFT", 0, -HEADER_H)
	bar:SetPoint("TOPRIGHT", 0, -HEADER_H)
	bar:SetHeight(TABS_H)
	S.Rule(bar, "BOTTOM")
	f.tabs = {}
	for i, tab in ipairs(TABS) do
		local b = CreateFrame("Button", nil, bar)
		b:SetHeight(TABS_H)
		if i == 1 then b:SetPoint("BOTTOMLEFT", 0, 0) else b:SetPoint("LEFT", f.tabs[i - 1], "RIGHT", 0, 0) end
		b.label = S.Text(b, "normal", C.muted)
		b.label:SetPoint("LEFT", PAD, 0)
		b.label:SetText(tab.label)
		b.underline = S.Solid(b, "OVERLAY", C.accent)
		b.underline:SetHeight(2)
		b.underline:SetPoint("BOTTOMLEFT", 6, 0)
		b.underline:SetPoint("BOTTOMRIGHT", -6, 0)
		local hover = S.Solid(b, "HIGHLIGHT", C.hover)
		hover:SetAllPoints()
		b:SetScript("OnClick", function()
			PlaySound("igCharacterInfoTab")
			S.Dismiss()
			state.tab = tab.key
			state.message = nil
			Window.Render()
		end)
		f.tabs[i] = b
	end
end

local function createMain(f)
	local main = CreateFrame("Frame", nil, f)
	main:SetPoint("TOPLEFT", SIDEBAR_W, -TITLE_H)
	main:SetPoint("BOTTOMRIGHT")
	f.main = main
	createHeader(main)
	createTabBar(main)

	local bodyTop = HEADER_H + TABS_H + PAD
	f.notes = RA.Widgets.TextArea(main, "RotationAssistNotesScroll", Window.BODY_W, Window.BODY_H, function(text)
		local rotation = Window.Selected()
		if rotation then rotation.notes = text end
	end, "normal")
	f.notes:SetPoint("TOPLEFT", PAD, -bodyTop)
	f.editors = {}
	for key, module in pairs(EDITORS) do
		f.editors[key] = RA[module].Create(main, Window.BODY_W, Window.BODY_H)
		f.editors[key]:SetPoint("TOPLEFT", PAD, -bodyTop)
	end

	local footer = CreateFrame("Frame", nil, main)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(FOOTER_H)
	S.Rule(footer, "TOP")
	f.summary = S.Text(footer, "small", C.muted)
	f.summary:SetPoint("LEFT", PAD, 0)
	f.summary:SetPoint("RIGHT", -PAD, 0)
end

local function createEmpty(f)
	local empty = CreateFrame("Frame", nil, f)
	empty:SetPoint("TOPLEFT", SIDEBAR_W, -TITLE_H)
	empty:SetPoint("BOTTOMRIGHT")
	local title = S.Text(empty, "large")
	title:SetPoint("CENTER", 0, 50)
	title:SetJustifyH("CENTER")
	title:SetText("No Rotations Yet")
	local body = S.Text(empty, "normal", C.muted)
	body:SetPoint("TOP", title, "BOTTOM", 0, -10)
	body:SetWidth(380)
	body:SetJustifyH("CENTER")
	body:SetText("A rotation is a priority list: each press casts the first spell that's ready. Start a blank one, or start from an example and tune it.")
	local new = S.Button(empty, "New Rotation", "primary", 120, newRotation)
	new:SetPoint("TOP", body, "BOTTOM", 0, -16)
	f.empty = empty
end

local function create()
	S.RefreshFonts()
	local f = CreateFrame("Frame", "RotationAssistFrame", UIParent)
	frame = f
	f:SetSize(W, H)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	local pos = RA.db.window
	if pos then f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y) else f:SetPoint("CENTER", 0, 40) end
	S.Panel(f, C.window, C.border)
	tinsert(UISpecialFrames, "RotationAssistFrame")
	f:Hide()

	createTitleBar(f)
	createSidebar(f)
	createMain(f)
	createEmpty(f)

	f:SetScript("OnShow", function()
		PlaySound("igCharacterInfoOpen")
		Window.Render()
	end)
	f:SetScript("OnHide", function()
		PlaySound("igCharacterInfoClose")
		S.Dismiss()
	end)
	f:SetScript("OnUpdate", function(self)
		if self.dirty then Window.Render() end
	end)
	return f
end

function Window.Open(name)
	frame = frame or create()
	if name then Window.Select(name) end
	frame:Show()
	Window.Render()
end

function Window.Toggle()
	if frame and frame:IsShown() then frame:Hide() else Window.Open() end
end

function Window.ResetPosition()
	RA.db.window = nil
	if frame then
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", 0, 40)
	end
end

function Window.Frame()
	return frame
end
