local ADDON, NS = ...

local RA = { version = GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version") or "dev" }
NS.RA = RA
_G.RotationAssist = RA

-- Server modules hook in through the Set* and Add* functions below (and AddRuneCosts and AddFinishers); see
-- docs/MODULES.md.
local classProvider, specNameProvider
local pairNames = {}

-- fn() returns the character's classes in pick order, as class keys, for servers where a character has several.
function RA:SetClassProvider(fn)
	classProvider = fn
end

-- fn(group) returns a name for talent group `group`, or nil for none.
function RA:SetSpecNameProvider(fn)
	specNameProvider = fn
end

-- names = { Lich = { "DEATHKNIGHT", "MAGE" }, ... }: one name to show for a two-class pair.
function RA:AddClassNames(names)
	for name, pair in pairs(names) do
		pairNames[pair[1] .. "/" .. pair[2]] = name
		pairNames[pair[2] .. "/" .. pair[1]] = name
	end
end

function RA:PairName(a, b)
	return a and b and pairNames[a .. "/" .. b]
end

function RA:Print(fmt, ...)
	local msg = select("#", ...) > 0 and fmt:format(...) or fmt
	DEFAULT_CHAT_FRAME:AddMessage("|cffffc400Rotation Assist|r: " .. msg)
end

-- The character's classes in pick order, as class keys.
function RA:PlayerClasses()
	local classes = classProvider and classProvider()
	if not classes or #classes == 0 then classes = { select(2, UnitClass("player")) } end
	return classes
end

function RA:HasClass(key)
	local found = false
	for _, k in ipairs(self:PlayerClasses()) do
		if k == key then found = true end
	end
	return found
end

function RA:Fits(rotation)
	local fits = true
	for _, class in ipairs(rotation.classes or {}) do
		if not self:HasClass(class) then fits = false end
	end
	return fits
end

local function className(key)
	return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[key] or key
end

-- Class names in class colors, or plain: a module's name for a two-class pair, otherwise each class.
function RA:ClassText(classes, plain)
	classes = classes or {}
	local pairName = #classes == 2 and self:PairName(classes[1], classes[2])
	local first = classes[1] and RAID_CLASS_COLORS[classes[1]]
	local function paint(c, text)
		return (not plain and c) and ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, text) or text
	end
	local text
	if pairName then
		text = paint(first, pairName)
	else
		local parts, seen = {}, {}
		for _, key in ipairs(classes) do
			if not seen[key] then
				seen[key] = true
				parts[#parts + 1] = paint(RAID_CLASS_COLORS[key], className(key))
			end
		end
		text = table.concat(parts, " / ")
	end
	return text
end

function RA:ActiveGroup()
	return GetActiveTalentGroup and GetActiveTalentGroup(false, false) or 1
end

function RA:SpecCount()
	return GetNumTalentGroups and GetNumTalentGroups(false, false) or 1
end

function RA:SpecName(group)
	local name = specNameProvider and specNameProvider(group)
	return ("Spec %d"):format(group) .. ((name and name ~= "") and (": " .. name) or "")
end

local function charKey()
	return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

-- This character's spec-to-rotation links, kept in the account file so renames and deletes reach every character.
function RA:Links()
	local key = charKey()
	self.db.links[key] = self.db.links[key] or {}
	return self.db.links[key]
end

function RA:LinkedSpecs(name)
	local groups = {}
	for group, linked in pairs(self:Links()) do
		if linked == name and group <= self:SpecCount() then groups[#groups + 1] = group end
	end
	table.sort(groups)
	return groups
end

-- Links a rotation to one spec on this character (replacing its other links), or unlinks it when group is nil.
function RA:LinkSpec(name, group)
	local links = self:Links()
	for g, linked in pairs(links) do
		if linked == name then links[g] = nil end
	end
	if group then links[group] = name end
	self:Changed()
end

-- The rotation linked to the active spec, if there is one.
function RA:ActiveRotation()
	local name = self:Links()[self:ActiveGroup()]
	return name and self.db.rotations[name]
end

-- Anything that changes a rotation, a link or a setting ends here: the button is rebuilt (after combat, if need be)
-- and the window redraws.
function RA:Changed()
	if self.Engine then self.Engine.Request() end
	if self.Window then self.Window.Refresh() end
end

local frame = CreateFrame("Frame")
RA.frame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" and name == ADDON then
		RotationAssistDB = RotationAssistDB or {}
		local db = RotationAssistDB
		db.rotations = db.rotations or {}
		db.links = db.links or {}
		db.button = db.button or { shown = true, locked = true, scale = 1 }
		if db.quiet == nil then db.quiet = true end
		RotationAssistCharDB = RotationAssistCharDB or {}
		RotationAssistCharDB.keys = RotationAssistCharDB.keys or {}
		RA.db, RA.charDB = db, RotationAssistCharDB
		self:UnregisterEvent("ADDON_LOADED")
	end
end)
