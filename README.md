# Rotation Assist

One-button rotations for WoW 3.3.5a, made for accessibility. Bind one key, or click one big on-screen button, and each press casts the first spell in
your priority list that's ready.

## Features

- **Priority Lists:** each press tries your actions from the top down and casts the first one that's ready. A
  press during the global cooldown does nothing, so mashing the key is safe.
- **Modes:** keep separate lists, like single target and AoE, or one for a form. Switch with a Mode key that can
  also cast a spell on the way, or automatically with a macro condition rule.
- **Off-GCD Lines:** trinkets, racials and cooldowns like Empower Rune Weapon fire alongside the main spell.
- **Sequences and Steps:** `/castsequence` blocks, and Steps blocks that run one line per press.
- **Rotation Button:** a large on-screen button showing the likely next spell, the mode and the key. You can
  click it like the key, and resize or move it.
- **Quiet Errors:** hides the "Not ready yet" errors that a priority list causes on purpose.
- **Per Spec:** link a rotation to a talent spec, and it switches with your spec.
- **Preview:** see exactly which macro each mode runs on your character, and which spells were left out
  because you don't know them.

## What a Button Can and Can't Do on 3.3.5a

The game decides what an addon may do in combat, and in 3.3.5a addons can't choose spells while you fight.
Instead, the button runs a macro built before the fight. The macro skips any spell that can't be cast: one on
cooldown, one you lack the runes, rage or mana for, a reactive ability that isn't lit (Execute, Overpower, Kill
Shot), or one out of range. It casts the first one left.

So the button can't react to procs, buffs, debuffs or target health on its own. It can't prefer Howling Blast
when Rime procs, or refresh diseases when they're about to fall off. If something a macro condition can see
changes (a form, a stance, a modifier key, your target), a condition rule can switch modes. For a buff, use the
Mode key. Every cast still needs a key press.

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
- `/rota minimap`: show or hide the minimap button
- `/rota reset`: move the window and the Rotation Button back to the middle of the screen

## License

MIT
