local ADDON, NS = ...
local RA = NS.RA

-- The style kit (UI/Style.lua, vendored from MaterialCraftUI) puts itself on the addon table, and its skins
-- (UI/Skins) register with it.
local S = NS.Style
RA.Style = S

-- The shared yellow theme of these addons: the Material 3 dark scheme for seed #ffc400, with surfaces from the
-- Neutral scheme, primary from the Fidelity scheme and error from the baseline. Skins with a scheme of their own,
-- such as Cognac and Classic, use theirs instead.
local YELLOW = {
	surfaceLowest = "0f0e0c", surface = "151311", surfaceLow = "1d1b19", surfaceContainer = "211f1d",
	surfaceHigh = "2c2a27", onSurface = "e7e1dd", onSurfaceVariant = "cbc6c1", outline = "94908c",
	outlineVariant = "494643", primary = "ffc400", onPrimary = "3f2e00", error = "ffb4ab", errorContainer = "93000a",
}
S.SetTheme(YELLOW)

local function known(key)
	for _, skin in ipairs(S.Skins()) do
		if skin.key == key then return true end
	end
	return false
end

-- The saved skin goes on once saved data is loaded (Core's handler runs first), before anything is built; frames
-- take their look when they're made.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
	if name == ADDON then
		if not known(RA.db.skin) then RA.db.skin = "material" end
		if RA.db.pixelScale == nil then RA.db.pixelScale = true end
		S.UseSkin(RA.db.skin, YELLOW)
		self:UnregisterEvent("ADDON_LOADED")
	end
end)

StaticPopupDialogs.ROTATION_ASSIST_RELOAD = {
	text = "Rotation Assist switches to the %s theme after a reload. Reload now?",
	button1 = "Reload",
	button2 = "Later",
	OnAccept = function() ReloadUI() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

-- Saves a skin for the next load and offers to reload. Returns false for a skin that doesn't exist.
function RA.SetSkin(key)
	local ok = known(key)
	if ok and key ~= RA.db.skin then
		RA.db.skin = key
		local label = key
		for _, skin in ipairs(S.Skins()) do
			if skin.key == key then label = skin.label end
		end
		StaticPopup_Show("ROTATION_ASSIST_RELOAD", label)
	end
	return ok
end

-- The window and dialogs are pixel-scaled (S.PixelScale) unless the player turned it off, so their edges and 1px
-- borders land on whole screen pixels. RA.PixelScale registers one as it's made.
local pixelFrames = {}

function RA.PixelScale(frame)
	pixelFrames[#pixelFrames + 1] = frame
	S.PixelScale(frame, RA.db.pixelScale)
	return frame
end

-- Snaps a window's position to whole pixels, when pixel scaling is on.
function RA.SnapPosition(frame)
	if RA.db.pixelScale then S.SnapPosition(frame) end
end

function RA.SetPixelScale(on)
	RA.db.pixelScale = on
	for _, frame in ipairs(pixelFrames) do
		S.PixelScale(frame, on)
		RA.SnapPosition(frame)
	end
end
