# Writing a Server Module

Rotation Assist only uses the stock 3.3.5a client API, so it runs on any Wrath server as it is. A server module
is a small addon that tells it about the parts of your server that stock 3.3.5a doesn't have:

- characters with more than one class
- names for talent specs
- custom spells that cost runes, or that need combo points

Modules live in repos of their own. [RotationAssist-Synastria](https://github.com/iExpulsion/RotationAssist-Synastria)
is one to copy: the addon folder and a workflow that releases a zip when its version goes up.

## The Addon

A module is a folder in `Interface\AddOns`, named `RotationAssist_<Server>`, with a `.toc` that depends on
Rotation Assist so it loads after it:

```
## Interface: 30300
## Title: Rotation Assist: My Server
## Notes: My Server's classes and spells for Rotation Assist.
## Version: 1.0.0
## Dependencies: RotationAssist

MyServer.lua
```

The Lua file calls the hooks on the `RotationAssist` global while it loads. Call only the ones your server needs.

## Hooks

### Classes

```lua
RotationAssist:SetClassProvider(function()
	return { "WARRIOR", "MAGE" }
end)
```

The function returns the character's classes as class keys (`"WARRIOR"`, `"DEATHKNIGHT"`, and so on), in the order
the player picked them. Rotations are grouped by class and marked as fitting when the character has every class
they list, and a new or imported rotation without classes takes the character's. Rotation Assist calls the
function whenever it needs the classes, so it can read the server's API each time. If the function is missing or
returns an empty list, the character has the one class `UnitClass("player")` reports.

### Class Pair Names

```lua
RotationAssist:AddClassNames({
	Battlemage = { "WARRIOR", "MAGE" },
	Spellblade = { "ROGUE", "MAGE" },
})
```

A name to show for a rotation made for two classes, in either order. Without one, the sidebar lists both
classes ("Warrior / Mage").

### Spec Names

```lua
RotationAssist:SetSpecNameProvider(function(group)
	return MyServerSpecName(group)
end)
```

`group` is the talent group (1, 2, and more where the server allows it). Return a name, or nil for none. Specs
show as "Spec 2: Tank" with a name and "Spec 2" without one.

### Rune Costs

```lua
RotationAssist:AddRuneCosts({
	["Frost Nova Strike"] = { frost = 1 },
	["Unholy Cleave"] = { frost = 1, unholy = 1 },
})
```

The client says a Death Knight spell is usable while its runes are still recharging, so Rotation Assist keeps a
table of rune costs for the Rotation Button and Smart Picks. Stock spells are already in it; add your server's
custom ones, or a stock spell whose cost your server changed. Kinds are `blood`, `frost` and `unholy`; death runes
stand in for any of them.

### Finishers

```lua
RotationAssist:AddFinishers({ "Shadow Flurry" })
```

Spells that need combo points. The client says a finisher is usable at 0 combo points, so Smart Picks passes over
the ones in this list until there's at least one. The stock Rogue and Druid finishers are already in it.

## Testing

Load the game with both addons, open `/rota`, and check:

- the sidebar groups your rotations under the right classes, or the pair's name
- the spec dropdown at the top of a rotation shows the spec names
- `/rota trace` while you mash a rotation with your custom spells

## Releasing

Copy RotationAssist-Synastria, rename the folder and the `.toc`, and put your hooks in the Lua file. Raising
`## Version` and pushing to `main` releases a zip. Then open an issue or a pull request on Rotation Assist to add
your module to the README's list.
