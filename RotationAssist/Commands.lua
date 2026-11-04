local _, NS = ...
local RA = NS.RA

local function help()
	RA:Print("v%s commands (/rota alone opens the window):", RA.version)
	RA:Print("  /rota button (show or hide the Rotation Button) | lock | unlock")
	RA:Print("  /rota macros | quiet | trace | minimap | reset")
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
handlers.minimap = function() RA.MinimapButton.Toggle() end
handlers.reset = function()
	RA.Window.ResetPosition()
	RA.RotationButton.ResetPosition()
	RA:Print("Window and Rotation Button moved back to the middle of the screen.")
end

SLASH_RA1 = "/rota"
SLASH_RA2 = "/rotationassist"
SlashCmdList.RA = function(msg)
	local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	local handler = handlers[cmd:lower()]
	if handler then handler(arg) else help() end
end
