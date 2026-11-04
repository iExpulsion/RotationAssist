# Rotation Assist

One-button rotations for WoW 3.3.5a, made for accessibility. Bind one key, or click one big on-screen button, and each press casts the first spell in
your priority list that's ready.

## Features

- **Priority Lists:** each press tries your actions from the top down and casts the first one that's ready. A
  press during the global cooldown does nothing, so mashing the key is safe.
- **Modes:** keep separate lists, like single target and AoE, or one for a form. Switch with a Mode key that can
  also cast a spell on the way, or automatically with a macro condition rule.
- **One Spell per Press:** for Death Knights and anything else a plain list can't get past. Each press tries the
  next spell in a cycle that returns to the top ones most often (1, 1 2, 1 2 3...), like GSE's Priority
  sequences, so mashing the key gives every spell its turn.
- **Off-GCD Lines:** trinkets, racials and cooldowns like Empower Rune Weapon fire alongside the main spell.
- **Sequences and Steps:** `/castsequence` blocks, and Steps blocks that run one line per press. A sequence
  can be **Once per Reset**: it casts each spell once (diseases, a mark), then waits until a new target or the
  next fight.
- **Rotation Button:** a large on-screen button showing the likely next spell, the mode and the key. You can
  click it like the key, and resize or move it.
- **Hints:** give a spell a hint like `[buff:Freezing Fog]` or `[nodebuff:Blood Plague<3]`, and the Rotation
  Button glows and shows that spell while the hint holds. Hints can check your buffs, your debuffs on the target,
  power and health, debuffs from anyone (`[noanydebuff:Mark of Frost]`), and for spells that leave no aura to
  see, whether you've cast them on this target this fight (`[nocast:Icy Touch]`). `[enemies>=3]` counts the
  enemies you've hit or that hit you in the last few seconds, so one mode can switch to AoE spells on a pack
  (mobs nothing has touched yet don't count). With Smart Picks on, a press
  casts what the button shows; without it, hints only change the button.
- **Smart Picks:** each press casts the spell the Rotation Button suggests, hints included, so a rotation can
  react to procs, debuffs, runes and cooldowns. It works by clearing your target for an instant before every
  line it didn't pick (a line conditioned on `[exists]` then can't cast) and retargeting right after, so target
  frames flicker while you mash, and it needs a target to cast.
- **Import and Export:** share a rotation, with all its modes, actions, hints and notes, as one string. Export
  and Import are at the bottom of the rotation list.
- **Quiet Errors:** hides the "Not ready yet" errors that a priority list causes on purpose.
- **Per Spec:** link a rotation to a talent spec, and it switches with your spec.
- **Preview:** see exactly which macro each mode runs on your character, and which spells were left out
  because you don't know them.

## What a Button Can and Can't Do on 3.3.5a

The game decides what an addon may do in combat, and in 3.3.5a addons can't choose spells while you fight.
Instead, the button runs a macro built before the fight. The macro skips any spell that can't be cast: one on
cooldown, one you lack the runes, rage or mana for, a reactive ability that isn't lit (Execute, Overpower, Kill
Shot), or one out of range. It casts the first one left.

So a plain list can't react to procs, buffs, debuffs or target health. It can't prefer Howling Blast when Rime
procs, or refresh diseases when they're about to fall off. If something a macro condition can see changes (a
form, a stance, a modifier key, your target), a condition rule can switch modes. For a buff, use the Mode key.
Smart Picks gets around this with the target trick above; without it, hints only change what the button shows.
Every cast still needs a key press.

## Installation

1. Download the latest release.
2. Extract the `RotationAssist` folder into `World of Warcraft\Interface\AddOns`.
3. Restart the game, or log out to the character screen and back in.

## Getting Started

1. Open the window with `/rota` or the minimap button and click **New Rotation**. Start blank, or from an
   example.
2. On the **Actions** tab, drag spells in from your spellbook or type their names, and order them from most to
   least important. Mark trinkets and other off-GCD actions as **Off the Global Cooldown**.
3. On the **Keys** tab, set the **Rotation Key** (and a **Mode Key** if you use modes), or make the action bar
   macros.
4. Click **Use Rotation** to link it to your active spec.

Changes made in combat apply as soon as combat ends.

## Commands

- `/rota`: open or close the window
- `/rota button`: show or hide the Rotation Button
- `/rota lock`, `/rota unlock`: lock or unlock the Rotation Button's position
- `/rota macros`: make the RA Rotation and RA Mode macros
- `/rota quiet`: turn Quiet Errors on or off
- `/rota trace`: after each press, list the spells sent, cast or failed, and the errors, to see which line took
  the press
- `/rota minimap`: show or hide the minimap button
- `/rota reset`: move the window and the Rotation Button back to the middle of the screen

## License

MIT
