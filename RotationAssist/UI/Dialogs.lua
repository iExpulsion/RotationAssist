local _, NS = ...
local RA = NS.RA

-- The New Rotation sheet, the Export and Import sheet, and the confirmation popups.
local Dialogs = {}
RA.Dialogs = Dialogs

local S = RA.Style
local C = S.colors
local GAP, CONTROL_H = S.GAP, S.CONTROL_H
local W, H = 380, 130

local sheet

local function create()
	-- the theme's dialog padding; the dialog grows by the difference from the kit's, so its contents keep their size
	local PAD = S.metrics.inset
	local grow = 2 * (PAD - S.PAD)
	S.RefreshFonts()
	local f = CreateFrame("Frame", "RotationAssistNewFrame", UIParent)
	f:SetSize(W + grow, H + grow)
	f:SetPoint("CENTER", 0, 80)
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	RA.PixelScale(f)
	S.Frame(f, "popup")
	tinsert(UISpecialFrames, "RotationAssistNewFrame")
	f:HookScript("OnHide", S.Dismiss)

	local title = S.Text(f, "large")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText("New Rotation")

	local nameLabel = S.Text(f, "small", C.muted)
	nameLabel:SetPoint("TOPLEFT", PAD, -(PAD + 16 + S.PAD + 6))
	nameLabel:SetText("Name")
	f.name = S.Input(f, "RotationAssistNewName", W - 2 * S.PAD - 80, "Rotation Name", 40)
	f.name:SetPoint("TOPLEFT", PAD + 80, -(PAD + 16 + S.PAD))

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
			f.onCreate(name)
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
	sheet.name:SetText(RA.Rotation.UniqueName("New Rotation"))
	sheet.name:UpdatePlaceholder()
	sheet.note:SetText("")
	sheet:Show()
end

function Dialogs.NewFrame()
	return sheet
end

-- The Export and Import sheet: one text box that holds a rotation string to copy, or takes one pasted in.
local SHARE_W, SHARE_H = 560, 300
local share, measure

-- The box only wraps at spaces and some punctuation, and a rotation string has long runs of neither, so it's
-- broken into lines no wider than `width` (as measureWidth reports them). Import ignores the line breaks.
function Dialogs.FitLines(text, width, measureWidth)
	local lines, line = {}, ""
	for i = 1, #text do
		local c = text:sub(i, i)
		if line ~= "" and measureWidth(line .. c) > width then
			lines[#lines + 1] = line
			line = c
		else
			line = line .. c
		end
	end
	lines[#lines + 1] = line
	return table.concat(lines, "\n")
end

local function fitToBox(text, edit)
	measure = measure or UIParent:CreateFontString(nil, "OVERLAY")
	if edit.GetFont and edit:GetFont() then measure:SetFont(edit:GetFont()) end
	return Dialogs.FitLines(text, (edit:GetWidth() or 0) - 4, function(s)
		measure:SetText(s)
		return measure:GetStringWidth() or 0
	end)
end

-- Import: checks the pasted string as it changes, and only offers Import once it reads.
local function refreshImport(f)
	local text = f.box.edit:GetText() or ""
	local rotation, err = RA.Codec.Decode(text)
	if rotation then
		local who = #(rotation.classes or {}) > 0 and RA:ClassText(rotation.classes, true) or "No Classes Listed"
		f.note:SetText(S.Hex(C.good, rotation.name .. ": ") .. who)
		f.import:Enable()
	else
		f.note:SetText(text:gsub("%s", "") == "" and "" or S.Hex(C.bad, err))
		f.import:Disable()
	end
	if f.mode == "import" and text == "" then f.placeholder:Show() else f.placeholder:Hide() end
end

-- Title and instructions, Close at the top right, the string, and a footer with a note on the left and the action
-- (Select All or Import) on the right.
local function createShare()
	local PAD = S.metrics.inset
	local grow = 2 * (PAD - S.PAD)
	S.RefreshFonts()
	local wellTop = PAD + 16 + 4 + 12 + GAP
	local footerH = PAD + CONTROL_H + PAD
	local f = CreateFrame("Frame", "RotationAssistShareFrame", UIParent)
	f:SetSize(SHARE_W + grow, SHARE_H + grow)
	f:SetPoint("CENTER", 0, 80)
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	RA.PixelScale(f)
	S.Frame(f, "popup")
	tinsert(UISpecialFrames, "RotationAssistShareFrame")
	f:HookScript("OnHide", S.Dismiss)

	f.title = S.Text(f, "large")
	f.title:SetPoint("TOPLEFT", PAD, -PAD)
	f.sub = S.Text(f, "small", C.muted)
	f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
	-- the close button's box lines up with the title's middle
	f.close = S.Button(f, "Close", "ghost", 56, function() f:Hide() end)
	f.close:SetPoint("TOPRIGHT", -PAD, -(PAD - 4))

	f.box = RA.Widgets.TextArea(f, "RotationAssistShareText", SHARE_W - 2 * S.PAD, SHARE_H + grow - wellTop - footerH, nil,
		"edit")
	f.box:SetPoint("TOPLEFT", PAD, -wellTop)
	f.box.edit:HookScript("OnTextChanged", function(self, userInput)
		if f.mode == "import" then
			refreshImport(f)
		elseif userInput and f.exported then
			self:SetText(f.exported)
			self:HighlightText()
		end
	end)
	f.box.edit:HookScript("OnEditFocusGained", function(self)
		if f.mode == "export" then self:HighlightText() end
	end)
	-- 3.3.5 gives addons no clipboard access, so the best is selecting the text and confirming the Ctrl+C
	f.box.edit:HookScript("OnKeyDown", function(_, key)
		if f.mode == "export" and key == "C" and IsControlKeyDown() then
			f.note:SetText(S.Hex(C.good, "Copied: Paste It Anywhere with Ctrl+V"))
		end
	end)
	f.placeholder = S.Text(f.box, "normal", C.muted)
	f.placeholder:SetPoint("CENTER")
	f.placeholder:SetText("Click here, then press Ctrl+V.")

	f.note = S.Text(f, "small", C.muted)
	f.note:SetPoint("LEFT", f, "BOTTOMLEFT", PAD, footerH / 2)
	f.note:SetJustifyH("LEFT")
	f.import = S.Button(f, "Import", "primary", 100, function()
		local rotation, err = RA.Codec.Decode(f.box.edit:GetText())
		if rotation then
			rotation.name = RA.Rotation.UniqueName(rotation.name)
			f:Hide()
			f.onImport(rotation)
		else
			f.note:SetText(S.Hex(C.bad, err))
		end
	end, "Add the rotation, renamed if you already have one by that name.")
	f.import:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	f.selectAll = S.Button(f, "Select All", "primary", 100, function()
		f.box.edit:SetFocus()
		f.box.edit:HighlightText()
		f.note:SetText(S.Hex(C.warn, "Selected: Press Ctrl+C to Copy"))
	end, "Select the whole string, ready for Ctrl+C.")
	f.selectAll:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	f.note:SetPoint("RIGHT", f.import, "LEFT", -PAD, 0)
	return f
end

function Dialogs.ShowExport(rotation)
	S.Dismiss()
	share = share or createShare()
	local text = RA.Codec.Encode(rotation)
	share.mode = "export"
	share.title:SetText("Export: " .. rotation.name)
	share.sub:SetText("Select All, then Ctrl+C to copy. Share it with anyone who uses Rotation Assist.")
	share.placeholder:Hide()
	share.import:Hide()
	share.selectAll:Show()
	share.box.edit:ClearFocus()
	share.exported = fitToBox(text, share.box.edit)
	share.box.edit:SetText(share.exported)
	share.box.edit:SetCursorPosition(0)
	share.note:SetText(S.Count(#text, "Character"))
	share:Show()
end

-- onImport(rotation) gets the new rotation, already renamed if its name was taken.
function Dialogs.ShowImport(onImport)
	S.Dismiss()
	share = share or createShare()
	share.mode = "import"
	share.exported = nil
	share.onImport = onImport
	share.title:SetText("Import a Rotation")
	share.sub:SetText("Paste a Rotation Assist string, then click Import.")
	share.selectAll:Hide()
	share.import:Show()
	share.box.edit:ClearFocus()
	share.box.edit:SetText("")
	refreshImport(share)
	share:Show()
end

function Dialogs.ShareFrame()
	return share
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
