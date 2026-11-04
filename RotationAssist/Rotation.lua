local _, NS = ...
local RA = NS.RA

-- Rotations: one or more modes, each an ordered list of actions the button tries top to bottom.
--
-- rotation = { name, classes, modes = { { label, actions } }, switch, options, notes }
-- action   = { kind = "spell", spell, when, offGcd, trigger }   (trigger: see Triggers.lua; steers the suggestion and Smart Picks)
--          | { kind = "sequence", spells = { ... }, reset, when, once }   (once: stop after the last spell until reset)
--          | { kind = "steps", steps = { "line", ... } }
--          | { kind = "macro", text, offGcd }
-- switch   = { kind = "none" } | { kind = "toggle", spell } | { kind = "rule", rule = "[form:3] 2; 1" }
local Rotation = {}
RA.Rotation = Rotation

Rotation.MAX_MODES = 6
Rotation.KINDS = {
	{ value = "spell", text = "Spell", tooltip = "Cast one spell when it's ready." },
	{ value = "sequence", text = "Sequence", tooltip = "/castsequence: moves to the next spell only when a cast succeeds." },
	{ value = "steps", text = "Steps", tooltip = "One macro line per press, in order, whether or not it casts." },
	{ value = "macro", text = "Macro", tooltip = "A macro line run as it is, such as /use 13." },
}

function Rotation.New(name, classes)
	return {
		name = name,
		classes = classes or RA:PlayerClasses(),
		modes = { { label = "Main", actions = {} } },
		switch = { kind = "none" },
		options = { target = true, attack = true },
		notes = "",
	}
end

local function copy(value)
	local out = value
	if type(value) == "table" then
		out = {}
		for k, v in pairs(value) do out[k] = copy(v) end
	end
	return out
end
Rotation.Copy = copy

function Rotation.UniqueName(base)
	local name, n = base, 2
	while RA.db.rotations[name] do
		name = ("%s %d"):format(base, n)
		n = n + 1
	end
	return name
end

function Rotation.Add(rotation)
	RA.db.rotations[rotation.name] = rotation
	RA:Changed()
	return rotation
end

function Rotation.Rename(rotation, newName)
	local ok = newName ~= "" and newName ~= rotation.name and RA.db.rotations[newName] == nil
	if ok then
		local old = rotation.name
		RA.db.rotations[old] = nil
		rotation.name = newName
		RA.db.rotations[newName] = rotation
		for _, links in pairs(RA.db.links) do
			for g, linked in pairs(links) do
				if linked == old then links[g] = newName end
			end
		end
		RA:Changed()
	end
	return ok
end

function Rotation.Duplicate(rotation)
	local dup = copy(rotation)
	dup.name = Rotation.UniqueName(rotation.name .. " Copy")
	return Rotation.Add(dup)
end

function Rotation.Delete(rotation)
	RA.db.rotations[rotation.name] = nil
	for _, links in pairs(RA.db.links) do
		for g, linked in pairs(links) do
			if linked == rotation.name then links[g] = nil end
		end
	end
	RA:Changed()
end

function Rotation.AddMode(rotation, label)
	local ok = #rotation.modes < Rotation.MAX_MODES
	if ok then rotation.modes[#rotation.modes + 1] = { label = label, actions = {} } end
	return ok
end

-- Swaps list[i] with list[i + delta] when both exist.
function Rotation.Move(list, i, delta)
	local j = i + delta
	local ok = list[i] ~= nil and list[j] ~= nil
	if ok then list[i], list[j] = list[j], list[i] end
	return ok
end

-- A short label for an action in lists.
function Rotation.ActionText(action)
	local text
	if action.kind == "spell" then
		text = RA.Spells.Name(action.spell) or ("Spell #" .. tostring(action.spell))
	elseif action.kind == "sequence" then
		text = "Sequence: " .. RA.Spells.ListText(action.spells)
	elseif action.kind == "steps" then
		text = RA.Style.Count(#(action.steps or {}), "Step")
	else
		text = action.text ~= "" and action.text or "Empty Macro"
	end
	return text
end

function Rotation.ActionIcon(action)
	local spell = action.kind == "spell" and action.spell or action.kind == "sequence" and (action.spells or {})[1]
	return spell and RA.Spells.Icon(spell) or "Interface\\Icons\\INV_Misc_Note_01"
end
