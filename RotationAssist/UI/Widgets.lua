local _, NS = ...
local RA = NS.RA

-- Controls the editors share, built on the style kit: a labeled checkbox and a heading. (The text well is the
-- kit's S.TextArea.)
local Widgets = {}
RA.Widgets = Widgets

local S = RA.Style
local C = S.colors

-- A checkbox with a clickable label. onClick(on) gets the new state.
function Widgets.Toggle(parent, label, tooltip, onClick)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(S.CONTROL_H)
	row.check = S.Check(row, nil, function() row:Click() end)
	row.check:SetPoint("LEFT", 0, 0)
	row.check.tooltipText = tooltip
	row.label = S.Text(row, "small")
	row.label:SetPoint("LEFT", row.check, "RIGHT", S.GAP, 0)
	row.label:SetText(label)
	row:SetWidth(S.CHECK_H + S.GAP + row.label:GetStringWidth() + 4)
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
