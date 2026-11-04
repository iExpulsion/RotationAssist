local _, NS = ...
local RA = NS.RA

-- The Rotation and Mode keys (override bindings, per character) and the action bar macros that click the same
-- buttons. Bindings can't change in combat, so they're set when the buttons are rebuilt.
local Keys = {}
RA.Keys = Keys

Keys.MACROS = {
	main = { name = "RA Rotation", button = "RotationAssistButton" },
	toggle = { name = "RA Mode", button = "RotationAssistToggle" },
}

local owner = CreateFrame("Frame", "RotationAssistKeyOwner", UIParent)
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, UNKNOWN = true }
local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

function Keys.Get(which)
	return RA.charDB.keys[which]
end

function Keys.Text(which)
	local key = Keys.Get(which)
	return key and (GetBindingText and GetBindingText(key, "KEY_", 1) or key) or "Not Set"
end

function Keys.Apply()
	local applied = not InCombatLockdown()
	if applied then
		ClearOverrideBindings(owner)
		for which, macro in pairs(Keys.MACROS) do
			local key = Keys.Get(which)
			if key then SetOverrideBindingClick(owner, true, key, macro.button, "LeftButton") end
		end
	end
	return applied
end

function Keys.Set(which, key)
	RA.charDB.keys[which] = key
	if not Keys.Apply() then RA.Engine.pending = true end
	RA:Changed()
end

-- The key with its modifiers, as bindings name it ("ALT-CTRL-SHIFT-F").
function Keys.Name(key)
	return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
end

-- Waits for one key (or middle or side mouse button) and hands its binding name to onDone; Esc or a left or right
-- click cancels with nil. The catcher only takes the keyboard after the player asks to set a key.
local catcher
function Keys.Capture(onDone)
	if not catcher then
		catcher = CreateFrame("Button", "RotationAssistKeyCatcher", UIParent)
		catcher:SetAllPoints(UIParent)
		catcher:SetFrameStrata("FULLSCREEN_DIALOG")
		catcher:RegisterForClicks("AnyUp")
		catcher:Hide()
		local function finish(self, key)
			self:EnableKeyboard(false)
			self:Hide()
			if self.onDone then self.onDone(key) end
		end
		catcher:SetScript("OnKeyDown", function(self, key)
			if key == "ESCAPE" then
				finish(self, nil)
			elseif not MODIFIER_KEYS[key] then
				finish(self, Keys.Name(key))
			end
		end)
		catcher:SetScript("OnClick", function(self, button)
			local key = MOUSE_KEYS[button]
			finish(self, key and Keys.Name(key) or nil)
		end)
	end
	catcher.onDone = onDone
	catcher:Show()
	catcher:EnableKeyboard(true)
end

function Keys.Capturing()
	return catcher ~= nil and catcher:IsShown()
end

-- Makes (or updates) both macros and puts the Rotation one on the cursor, ready to drop on an action bar.
function Keys.MakeMacros()
	local result
	if InCombatLockdown() then
		result = "Can't Make Macros in Combat"
	else
		local first
		for _, which in ipairs({ "main", "toggle" }) do
			local macro = Keys.MACROS[which]
			local body = "/click " .. macro.button
			local index = GetMacroIndexByName(macro.name)
			if index and index > 0 then
				EditMacro(index, macro.name, 1, body)
			elseif (GetNumMacros()) < (MAX_ACCOUNT_MACROS or 36) then
				index = CreateMacro(macro.name, 1, body, nil)
			end
			if which == "main" then first = index end
		end
		if first and first > 0 then
			PickupMacro(first)
			result = "Macros Made: Drop RA Rotation on an Action Bar"
		else
			result = "Your General Macros Are Full"
		end
	end
	return result
end
