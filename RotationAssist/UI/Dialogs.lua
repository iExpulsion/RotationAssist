local _, NS = ...
local RA = NS.RA

-- The New Rotation sheet (a name and what to start from) and the confirmation popups.
local Dialogs = {}
RA.Dialogs = Dialogs

local S = RA.Style
local C = S.colors
local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H
local W, H = 380, 170
local BLANK = "\1blank"

local sheet

local function startOptions()
	local options = { { value = BLANK, text = "Blank", tooltip = "An empty rotation for your classes." } }
	for _, t in ipairs(RA.Rotation.TEMPLATES) do
		options[#options + 1] = { value = t.key, text = t.label, tooltip = "Example for " .. RA:ClassText(t.classes, true) .. ". Tune the order in game." }
	end
	return options
end

local function startLabel(value)
	local text = "Blank"
	for _, opt in ipairs(startOptions()) do
		if opt.value == value then text = opt.text end
	end
	return text
end

local function create()
	S.RefreshFonts()
	local f = CreateFrame("Frame", "RotationAssistNewFrame", UIParent)
	f:SetSize(W, H)
	f:SetPoint("CENTER", 0, 80)
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	S.Panel(f, { C.window[1], C.window[2], C.window[3], 1 }, C.border)
	tinsert(UISpecialFrames, "RotationAssistNewFrame")
	f:HookScript("OnHide", S.Dismiss)

	local title = S.Text(f, "large")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText("New Rotation")

	local nameLabel = S.Text(f, "small", C.muted)
	nameLabel:SetPoint("TOPLEFT", PAD, -(PAD + 16 + PAD + 6))
	nameLabel:SetText("Name")
	f.name = S.Input(f, "RotationAssistNewName", W - 2 * PAD - 80, "Rotation Name", 40)
	f.name:SetPoint("TOPLEFT", PAD + 80, -(PAD + 16 + PAD))

	local startLabelText = S.Text(f, "small", C.muted)
	startLabelText:SetPoint("TOPLEFT", nameLabel, "TOPLEFT", 0, -(CONTROL_H + GAP))
	startLabelText:SetText("Start From")
	f.start = S.Dropdown(f, W - 2 * PAD - 80, function(value)
		f.startValue = value
		f.start:SetText(startLabel(value))
		if not f.nameEdited then
			f.name:SetText(RA.Rotation.UniqueName(value == BLANK and "New Rotation" or startLabel(value)))
			f.name:UpdatePlaceholder()
		end
	end)
	f.start:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -GAP)
	f.name:HookScript("OnTextChanged", function(_, userInput)
		if userInput then f.nameEdited = true end
	end)

	local cancel = S.Button(f, "Cancel", "secondary", 80, function() f:Hide() end)
	cancel:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	f.create = S.Button(f, "Create", "primary", 80, function()
		local name = RA.Spells.Trim(f.name:GetText())
		if name == "" then
			f.note:SetText(S.Hex(C.bad, "Give It a Name"))
		elseif RA.db.rotations[name] then
			f.note:SetText(S.Hex(C.bad, "A Rotation Has That Name"))
		else
			f:Hide()
			f.onCreate(name, f.startValue ~= BLANK and f.startValue or nil)
		end
	end)
	f.create:SetPoint("RIGHT", cancel, "LEFT", -GAP, 0)
	f.name:SetScript("OnEnterPressed", function() f.create:Click() end)
	f.note = S.Text(f, "small", C.muted)
	f.note:SetPoint("LEFT", f, "BOTTOMLEFT", PAD, PAD + CONTROL_H / 2)
	return f
end

function Dialogs.ShowNew(onCreate)
	sheet = sheet or create()
	sheet.onCreate = onCreate
	sheet.nameEdited = false
	sheet.startValue = BLANK
	sheet.start:SetOptions(startOptions())
	sheet.start:SetText("Blank")
	sheet.name:SetText(RA.Rotation.UniqueName("New Rotation"))
	sheet.name:UpdatePlaceholder()
	sheet.note:SetText("")
	sheet:Show()
end

function Dialogs.NewFrame()
	return sheet
end

StaticPopupDialogs["RA_DELETE"] = {
	text = "Delete rotation \"%s\"?",
	button1 = DELETE,
	button2 = CANCEL,
	OnAccept = function(self) self.data() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

function Dialogs.Confirm(which, name, onAccept)
	local popup = StaticPopup_Show(which, name)
	if popup then popup.data = onAccept end
end
