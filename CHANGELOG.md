# Changelog

## 1.9.0

### Triggers and Conditions

- **Build Them from Rows:** **Add** (or **Edit**) beside **Trigger** or **Conditions** opens a sheet where each
  condition is a row of choices instead of typed syntax. A box holds conditions that must all hold, **+ And** adds
  one, and **+ Or** adds a box that will do instead. **Edit as Text** still takes the old syntax.
- **Picking Names:** the name box searches your spellbook and the auras on you and your target, or takes any name you
  type.
- **Plain-English Readback:** the Actions tab says what each trigger and condition means, such as "When your health is
  50% or less and you have Berserker Rage." Names use the game's spelling, and names the game knows are colored, so a
  typo stands out. Hover a readback to see all of it.
- **When Met:** Keep Its Place is now a **When Met** choice beside the trigger: **Jump Ahead** (as before) or **Stay in
  Place**. Under it, the pane names the spells a met trigger goes ahead of.
- **Grouped Menus:** the kinds of trigger and condition are sorted under headings (On You, On the Target, The Fight;
  The Unit, You, and so on). A menu too tall for your screen opens in columns.
- **Ground Spells:** conditions understand `@ploc`, `@cur` and `@tloc` and list Ground at Your Target.

### Actions Tab

- **Spell Name Suggestions:** typing a spell in the Add box or a Sequence's spell list shows matching spells from your
  spellbook. **Tab** or **Enter** takes the highlighted one.
- **Clearer Layout:** each action's details are in Conditions, Trigger and Options sections, with the Add or Edit
  button on the section's heading.
- **Lists:** the action list and the rotation list use the scroll bar's space when there's nothing to scroll.
- **Shorter Tooltips:** tooltips and hints throughout are shorter, and their examples no longer belong to one class.

## 1.8.1

### Fixes

- **UI Scale Addons:** With an addon that sets its own UI scale, such as DragonUI, Rotation Assist's windows came up
  at the wrong size after a login or reload until Snap to Pixels was toggled. They now follow the UI scale whenever it
  changes.
