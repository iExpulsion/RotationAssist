local _, NS = ...
local RA = NS.RA

local function themeNames()
	local names = {}
	for _, skin in ipairs(RA.Style.Skins()) do names[#names + 1] = skin.key end
	return table.concat(names, ", ")
end

local function help()
	RA:Print("v%s commands (/rota alone opens the window):", RA.version)
	RA:Print("  /rota button (show or hide the Rotation Button) | lock | unlock")
	RA:Print("  /rota macros | quiet | trace | minimap [reset] | reset")
	RA:Print("  /rota theme <name> (after a reload: %s) | pixel (snap the window to whole screen pixels)", themeNames())
end

local handlers = {}
handlers[""] = function() RA.Window.Toggle() end
handlers.help = help
handlers.button = function()
	RA.RotationButton.SetShown(not RA.db.button.shown)
	RA:Print(RA.db.button.shown and "Rotation Button shown." or "Rotation Button hidden. /rota button shows it again.")
end
handlers.lock = function()
	RA.RotationButton.SetLocked(true)
	RA:Print("Rotation Button locked.")
end
handlers.unlock = function()
	RA.RotationButton.SetLocked(false)
	RA:Print("Rotation Button unlocked: drag it out of combat, then /rota lock.")
end
handlers.macros = function() RA:Print(RA.Keys.MakeMacros()) end
handlers.quiet = function()
	RA.Quiet.Set(not RA.db.quiet)
	RA:Print(RA.db.quiet and "Quiet Errors on." or "Quiet Errors off.")
end
handlers.trace = function()
	if RA.Trace then
		RA:Print(RA.Trace.Toggle() and "Trace on: each press lists the spells sent, cast or failed, and the errors. /rota trace stops it."
			or "Trace off.")
	else
		RA:Print("Trace needs a full game restart after an update; /reload doesn't load new files.")
	end
end
handlers.minimap = function(arg)
	if arg:lower() == "reset" then RA.MinimapButton.ResetPosition() else RA.MinimapButton.Toggle() end
end
handlers.reset = function()
	RA.Window.ResetPosition()
	RA.RotationButton.ResetPosition()
	RA:Print("Window moved back to the top middle of the screen, and the Rotation Button under the middle.")
end
handlers.theme = function(arg)
	local key = arg:lower()
	if key == "" then
		RA:Print("Theme: %s. Themes: %s.", RA.Style.Skin(), themeNames())
	elseif not RA.SetSkin(key) then
		RA:Print("No theme called %s. Themes: %s.", key, themeNames())
	else
		RA:Print("Theme: %s. /reload if it hasn't switched yet.", key)
	end
end
handlers.pixel = function()
	RA.SetPixelScale(not RA.db.pixelScale)
	RA:Print(RA.db.pixelScale and "The window snaps to whole screen pixels." or
		"The window follows the UI scale exactly; borders may blur at some scales.")
end

SLASH_ROTATIONASSIST1 = "/rota"
SLASH_ROTATIONASSIST2 = "/rotationassist"
SlashCmdList.ROTATIONASSIST = function(msg)
	local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	local handler = handlers[cmd:lower()]
	if handler then handler(arg) else help() end
end
