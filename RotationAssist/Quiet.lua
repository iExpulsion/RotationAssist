local _, NS = ...
local RA = NS.RA

-- Quiet Errors: a priority macro fails on purpose for every line before the one that casts, so "Not ready yet"
-- and friends would fill the screen on every press. For a moment after each press of the rotation or mode
-- button, error messages are dropped, and while it's on the spoken error lines are off.
local Quiet = {}
RA.Quiet = Quiet

Quiet.WINDOW = 0.4
local quietUntil = 0

function Quiet.Pressed()
	quietUntil = GetTime() + Quiet.WINDOW
end

function Quiet.Active()
	return RA.db.quiet and GetTime() < quietUntil
end

local addMessage = UIErrorsFrame.AddMessage
UIErrorsFrame.AddMessage = function(self, ...)
	if not Quiet.Active() then return addMessage(self, ...) end
end

-- The spoken errors are a client setting; the player's own value comes back when Quiet Errors is turned off.
function Quiet.ApplySpeech()
	if GetCVar and SetCVar then
		if RA.db.quiet then
			if RA.db.savedErrorSpeech == nil then RA.db.savedErrorSpeech = GetCVar("Sound_EnableErrorSpeech") end
			SetCVar("Sound_EnableErrorSpeech", "0")
		elseif RA.db.savedErrorSpeech ~= nil then
			SetCVar("Sound_EnableErrorSpeech", RA.db.savedErrorSpeech)
			RA.db.savedErrorSpeech = nil
		end
	end
end

function Quiet.Set(on)
	RA.db.quiet = on and true or false
	Quiet.ApplySpeech()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
	Quiet.ApplySpeech()
	local exec, toggle = RA.Engine.Buttons()
	for _, b in ipairs({ exec, toggle }) do
		if b then b:HookScript("PreClick", Quiet.Pressed) end
	end
	self:UnregisterEvent("PLAYER_LOGIN")
end)
