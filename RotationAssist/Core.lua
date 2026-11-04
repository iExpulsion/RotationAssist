local ADDON, NS = ...

local RA = { version = GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version") or "dev" }
NS.RA = RA
_G.RotationAssist = RA

RA.CLASS_KEYS = {
	[1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE", [5] = "PRIEST",
	[6] = "DEATHKNIGHT", [7] = "SHAMAN", [8] = "MAGE", [9] = "WARLOCK", [11] = "DRUID",
}
RA.CLASS_IDS = {}
for id, key in pairs(RA.CLASS_KEYS) do RA.CLASS_IDS[key] = id end

-- Names for two-class pairs.
local COMBOS = {
	Champion = { "WARRIOR", "PALADIN" }, Soldier = { "WARRIOR", "HUNTER" }, Blademaster = { "WARRIOR", "ROGUE" },
	Crusader = { "WARRIOR", "PRIEST" }, Butcher = { "WARRIOR", "DEATHKNIGHT" }, Ravager = { "WARRIOR", "SHAMAN" },
	Battlemage = { "WARRIOR", "MAGE" }, Vanquisher = { "WARRIOR", "WARLOCK" }, Barbarian = { "WARRIOR", "DRUID" },
	Avenger = { "PALADIN", "HUNTER" }, Agent = { "PALADIN", "ROGUE" }, Martyr = { "PALADIN", "PRIEST" },
	Enforcer = { "PALADIN", "DEATHKNIGHT" }, Sentinel = { "PALADIN", "SHAMAN" }, Inquisitor = { "PALADIN", "MAGE" },
	Warden = { "PALADIN", "WARLOCK" }, Guardian = { "PALADIN", "DRUID" },
	Scout = { "HUNTER", "ROGUE" }, Seer = { "HUNTER", "PRIEST" }, Slayer = { "HUNTER", "DEATHKNIGHT" },
	Tempest = { "HUNTER", "SHAMAN" }, Arcanist = { "HUNTER", "MAGE" }, Trickster = { "HUNTER", "WARLOCK" },
	Ranger = { "HUNTER", "DRUID" },
	Herald = { "ROGUE", "PRIEST" }, Assassin = { "ROGUE", "DEATHKNIGHT" }, Ninja = { "ROGUE", "SHAMAN" },
	Spellblade = { "ROGUE", "MAGE" }, Voidstalker = { "ROGUE", "WARLOCK" }, Spy = { "ROGUE", "DRUID" },
	Wraith = { "PRIEST", "DEATHKNIGHT" }, Oracle = { "PRIEST", "SHAMAN" }, Mystic = { "PRIEST", "MAGE" },
	Siren = { "PRIEST", "WARLOCK" }, Empath = { "PRIEST", "DRUID" },
	Summoner = { "DEATHKNIGHT", "SHAMAN" }, Lich = { "DEATHKNIGHT", "MAGE" }, Necromancer = { "DEATHKNIGHT", "WARLOCK" },
	Dreadweaver = { "DEATHKNIGHT", "DRUID" },
	Elementalist = { "SHAMAN", "MAGE" }, Harbinger = { "SHAMAN", "WARLOCK" }, Sage = { "SHAMAN", "DRUID" },
	Sorcerer = { "MAGE", "WARLOCK" }, Conjurer = { "MAGE", "DRUID" },
	Witch = { "WARLOCK", "DRUID" },
}
local comboByPair = {}
for combo, pair in pairs(COMBOS) do
	comboByPair[pair[1] .. "/" .. pair[2]] = combo
	comboByPair[pair[2] .. "/" .. pair[1]] = combo
end

function RA:ComboName(a, b)
	return a and b and comboByPair[a .. "/" .. b]
end

function RA:Print(fmt, ...)
	local msg = select("#", ...) > 0 and fmt:format(...) or fmt
	DEFAULT_CHAT_FRAME:AddMessage("|cffffc400Rotation Assist|r: " .. msg)
end

-- The character's classes in pick order, as class keys.
function RA:PlayerClasses()
	local classes = {}
	local count = CMCGetClassCount and CMCGetClassCount() or 0
	if count >= 1 then
		for i = 1, count do
			local id = CMCGetClassAt(i)
			classes[#classes + 1] = (CMCGetClassKey and CMCGetClassKey(id)) or self.CLASS_KEYS[id]
		end
	else
		classes[1] = select(2, UnitClass("player"))
	end
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

-- Class names in class colors, or plain: the server's name for a two-class pair, otherwise each class.
function RA:ClassText(classes, plain)
	classes = classes or {}
	local combo = #classes == 2 and self:ComboName(classes[1], classes[2])
	local first = classes[1] and RAID_CLASS_COLORS[classes[1]]
	local function paint(c, text)
		return (not plain and c) and ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, text) or text
	end
	local text
	if combo then
		text = paint(first, combo)
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
	local name = GetCustomGameDataString and GetCustomGameDataString(21, group) or ""
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

-- Brings saved rotations up to date: spell actions' hint field was renamed trigger.
function RA:Migrate()
	for _, rotation in pairs(self.db.rotations) do
		for _, mode in ipairs(rotation.modes or {}) do
			for _, action in ipairs(mode.actions or {}) do
				if action.hint ~= nil then action.trigger, action.hint = action.trigger or action.hint, nil end
			end
		end
	end
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
		RA:Migrate()
		self:UnregisterEvent("ADDON_LOADED")
	end
end)
