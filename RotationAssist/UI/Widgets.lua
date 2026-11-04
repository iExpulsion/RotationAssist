local _, NS = ...
local RA = NS.RA

-- Controls the editors share, built on the style kit: a multi-line text well, a segmented switch and a labeled
-- checkbox.
local Widgets = {}
RA.Widgets = Widgets

local S = RA.Style
local C = S.colors

-- A scrolling multi-line edit box in a well. onChange(text) runs on typing; SetValue sets text without it.
function Widgets.TextArea(parent, name, width, height, onChange, fontSize)
	local box = CreateFrame("Frame", nil, parent)
	box:SetSize(width, height)
	S.Panel(box, C.well, C.border)
	local scroll = CreateFrame("ScrollFrame", name, box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -18, 8)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	S.SetFont(edit, fontSize or "small")
	edit:SetWidth(width - 26)
	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	edit:SetScript("OnEditFocusGained", function(self)
		self.focused = true
		box:SetBackdropBorderColor(unpack(C.accent))
	end)
	edit:SetScript("OnEditFocusLost", function(self)
		self.focused = false
		box:SetBackdropBorderColor(unpack(C.border))
	end)
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput and onChange then onChange(self:GetText()) end
	end)
	scroll:SetScrollChild(edit)
	S.TrackInput(edit, box)
	RA.List.AutoHideBar(scroll, name)
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function() edit:SetFocus() end)
	box.edit = edit
	function box:SetValue(text)
		if not edit.focused then edit:SetText(text or "") end
	end
	function box:SetReadOnly(on)
		edit:EnableMouse(not on)
		box:EnableMouse(not on)
		if on then edit:ClearFocus() end
	end
	return box
end

-- Buttons side by side that overlap by their 1px border; the selected one is drawn as "selected".
-- SetOptions({ { value, text, tooltip } }) and SetValue(value); clicking calls onSelect(value).
function Widgets.Segmented(parent, width, onSelect)
	local seg = CreateFrame("Frame", nil, parent)
	seg:SetSize(width, S.CONTROL_H)
	seg.buttons = {}
	function seg:SetOptions(options)
		local w = math.floor((width + #options - 1) / #options)
		for i, opt in ipairs(options) do
			local b = self.buttons[i]
			if not b then
				b = S.Button(self, "", "secondary", w)
				self.buttons[i] = b
			end
			b:SetWidth(w)
			b:ClearAllPoints()
			b:SetPoint("LEFT", (i - 1) * (w - 1), 0)
			b.label:SetText(opt.text)
			b.value = opt.value
			b.tooltipText = opt.tooltip
			b:SetScript("OnClick", function() onSelect(opt.value) end)
			b:Show()
		end
		for i = #options + 1, #self.buttons do self.buttons[i]:Hide() end
	end
	function seg:SetValue(value)
		for _, b in ipairs(self.buttons) do b:SetKind(b.value == value and "selected" or "secondary") end
	end
	return seg
end

-- A checkbox with a clickable label. onClick(on) gets the new state.
function Widgets.Toggle(parent, label, tooltip, onClick)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(S.CONTROL_H)
	row.check = S.Check(row, 14, function() row:Click() end)
	row.check:SetPoint("LEFT", 0, 0)
	row.check.tooltipText = tooltip
	row.label = S.Text(row, "small")
	row.label:SetPoint("LEFT", row.check, "RIGHT", S.GAP, 0)
	row.label:SetText(label)
	row:SetWidth(14 + S.GAP + row.label:GetStringWidth() + 4)
	row:SetScript("OnClick", function(self)
		if self.check.usable then onClick(not self.check.on) end
	end)
	row:SetScript("OnEnter", function(self)
		if tooltip then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	function row:SetChecked(on) self.check:SetChecked(on) end
	function row:SetEnabled(on)
		self.check:SetEnabled(on)
		self.label:SetTextColor(unpack(on and C.text or C.muted))
	end
	return row
end

-- A small heading in the accent color.
function Widgets.Heading(parent, text)
	local fs = S.Text(parent, "small", C.heading)
	fs:SetText(text)
	return fs
end
