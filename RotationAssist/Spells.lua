local _, NS = ...
local RA = NS.RA

-- Spells are stored by ID where one is known, so a rotation reads the same in any client language, and by name
-- otherwise (spells this character doesn't have yet). Names are what the macros cast: /cast Name picks the
-- highest rank the character knows.
local Spells = {}
RA.Spells = Spells

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local function trim(s)
	return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end
Spells.Trim = trim

local function idFromLink(link)
	return link and tonumber(link:match("|Hspell:(%d+)"))
end

-- The name a stored spell (ID or name) casts by, or nil for an ID the client doesn't know.
function Spells.Name(spell)
	local name
	if type(spell) == "number" then name = GetSpellInfo(spell) else name = spell end
	return name ~= "" and name or nil
end

-- True if the character has the spell in its spellbook: GetSpellInfo finds a name only in the spellbook.
function Spells.Known(name)
	return name ~= nil and GetSpellInfo(name) ~= nil
end

function Spells.Icon(spell)
	local name = Spells.Name(spell)
	local icon = name and select(3, GetSpellInfo(type(spell) == "number" and spell or name))
	return icon or QUESTION
end
Spells.QUESTION = QUESTION

-- Typed text to a stored spell: a number is an ID; a name the character knows becomes its ID; any other name is
-- kept as typed.
function Spells.FromText(text)
	text = trim(text)
	local id = tonumber(text)
	local spell
	if id then
		spell = id
	elseif text ~= "" then
		spell = idFromLink(GetSpellLink and GetSpellLink(text)) or text
	end
	return spell
end

-- A spell picked up from the spellbook (GetCursorInfo's "spell", slot, book) to a stored spell.
function Spells.FromCursor(kind, slot, book)
	local spell
	if kind == "spell" and slot then
		spell = idFromLink(GetSpellLink(slot, book))
		if not spell then spell = GetSpellName and GetSpellName(slot, book) end
	end
	return spell
end

-- Comma-separated spell text to a list of stored spells.
function Spells.ListFromText(text)
	local list = {}
	for part in (text or ""):gmatch("[^,]+") do
		local spell = Spells.FromText(part)
		if spell then list[#list + 1] = spell end
	end
	return list
end

function Spells.ListText(list)
	local names = {}
	for _, spell in ipairs(list or {}) do names[#names + 1] = Spells.Name(spell) or ("#" .. tostring(spell)) end
	return table.concat(names, ", ")
end
