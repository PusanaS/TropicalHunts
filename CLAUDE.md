# TropicalHunts — notes for Claude

A Godot 2D platformer, described by the team as a "juice game": you hunt monsters in the tropics and make juice from them.
Repo: https://github.com/PusanaS/TropicalHunts (owned by BOOM).

## Team (sprint 1)
- **BOOM** (GitHub: PusanaS), the lead. Designs the 2 main characters and animates the main character and the first monsters. He wrote the player controller and writes his code comments in Thai. Since 2026-09-29 he's focusing on art only.
- **varreaux** (Morgan, the person you're working with). Designs how each monster works, and the first levels.
- **Violeta**. Designs how the monsters look, the 3 juices, the juice-making minigame, and a "rich girl ref".
- **Programming** is done by Morgan, with Claude. BOOM said we can change his code.

## Rules
1. **BOOM's code is ours to change now:** `code/player.gd`, `scene/player.tscn`, `scene/test.tscn`. BOOM approved this on 2026-09-29.
   - **His art is still his.** Don't edit `Sprite/` or `workfile/*.aseprite`.
   - **`scene/player.tscn` also holds his animation setup** (the SpriteFrames). Tell Morgan when you change it, so it doesn't clash with BOOM's animation updates.
   - Keep his Thai comments.
2. **Design scenes go in `scene/design/`.** Add `scene/player.tscn` to them as an instance, not a copy. Don't turn on "Editable Children".
3. **Don't change the main scene** or settings in `project.godot`. Morgan runs individual scenes with Cmd+R ("Run Current Scene").
4. **Monster art and animation belong to Violeta and BOOM.** Anything we make is a placeholder. Label it that way.
5. **Don't commit, create branches, or push** without asking.
6. **Don't open game windows.** Morgan runs the game from the Godot editor, and `LiveReload` picks up script and scene changes on its own. Tell Morgan when a change is ready to view and whether it needs Cmd+R: new images do, and so do scenes without a LiveReload node.
7. **Work in quick rounds, and Morgan does the testing.** Don't write test scripts or run headless test runs unless Morgan asks. Make the change, then say what changed, what to try in the game, and whether it needs Cmd+R. Morgan plays it and reports back.
8. **Explain things in plain language.** "Just give me your thoughts" means don't change anything.

## Godot
- **Version:** 4.7.2, at `/Applications/Godot.app/Contents/MacOS/Godot`. The team is moving to 4.7, so use it directly.
- **Run a scene:** `Godot --path . res://scene/design/gym_movement.tscn`. Only do this if Morgan asks (see rule 6).
- **Headless tests (only when Morgan asks, see rule 7):** write a test script that extends `SceneTree` in `.godot/claude_tmp/`, which git ignores. Run it with `Godot --headless --path . -s .godot/claude_tmp/test.gd`, then delete it.
  - Fake key presses with `Input.parse_input_event()` and an `InputEventKey`. Don't use `Input.action_press()`: the player code's `is_action_just_pressed` misses it, so tests fail when nothing is wrong.
  - Remove the scene's LiveReload node inside the test, or a file change will restart the scene in the middle of it.
- **New scripts:** run `Godot --headless --path . --import` so Godot creates the `.gd.uid` ID file.
- **Controls:** arrow keys move, Space/Enter jumps (`ui_accept`), Q is the light attack, W the heavy attack. Q and W are added by code in `player.gd`'s `_ready`, not in the Input Map.
- **Display:** 1920×1080 at 4× scale, so 480×270 pixels of the game world are visible. Pixel-art (nearest) filtering, GL Compatibility renderer.

## Player numbers
These come from `player.gd`, with Godot's default gravity of 980.
- **Speeds:** walk 120 px/s. Run 260 after holding a direction for 1s. Sprint 420 after 1.9s.
- **Double-tap a direction:** run instantly, and sprint 0.5s later.
- **Jump height:** about 103px. The double jump adds about 82px, for about 185px in total.
- **Full jump distance:** walking about 110px, running about 240px, sprinting about 385px.
- **Size:** the player is about 40px tall, and the node's origin is at the feet.
- **View limits:** at sprint speed you see only about 0.57s ahead. From 256px up, you can't see the ground.
- **Air attacks (added 2026-09-29):** Q in the air does the light combo with no lunge, keeping your drift, then goes back to falling. Landing in the middle of it cancels it into LAND (tracked by `light_in_air`, added by the ENEMY session). W in the air goes straight into `DASH_ATTACK_HEAVY_SLAM`: an immediate slam down with a big-shake impact, with no hop or hover (Morgan's call). The running W on the ground still has its hop and hover. The sprint flash still only triggers on the ground.

## What we've added
- **`scene/design/gym_movement.tscn`:** a movement test room with ledges from 32 to 192px, a 1600px runway, gaps from 96 to 416px, low ceilings, a 256px drop, monster-size blocks and flying monster heights.
- **`code/live_reload.gd`:** a tool for development only. Add it as a Node in a scene. While the game runs, it reloads changed scripts and scenes from disk, keeps the position of the node named `Player`, and does nothing in exported builds.
- **The Thunderclap flash, in `player.gd`** (`_try_flash` and `_flash_strike`, settings in the `FLASH_*` constants). It's Morgan's idea, based on Zenitsu's move from *Demon Slayer*.
  - **Trigger:** at full sprint, holding a direction, with an enemy up to 120px ahead. The flash happens instantly, with no pause (Morgan's call, 2026-09-29). It hits every enemy in its path and lands just past the last one, 160–240px away.
  - **Walls and pits:** it stops at walls and never lands over a pit.
  - **After:** the player comes out of it still sprinting (also Morgan's call). There's no cooldown, so flashes can chain through groups of enemies.
  - **Visuals:** made in code: a yellow streak along the path, a spark burst where it lands, and screen shake. It has no state or animation of its own.
- **The counter, in `player.gd`** (`_try_counter`, `COUNTER_*` constants). Press Q while an enemy is mid-lunge within 96px: the player turns to face it and does one massive horizontal slash on the spot. There's no teleport and no horizontal movement: the player's horizontal speed drops to 0 (Morgan's call).
  - **The slash:** the player plays the `ATTACK_LIGHT_2` swing. The slash starts as a sword arc at chest height (20px above the feet), swinging from over the shoulder round to the front, then shoots out straight, up to 320px and stopped by walls. It's thin: a 12px glow with a 3px core. It cuts in half every enemy in that line within 64px of the player's height. Morgan's friend asked for this.
  - **What it hits:** only enemies with `cut_in_half()`, so the boss isn't hit. It works from any state except the heavy attacks, including in the air. It's Morgan's idea, added 2026-09-29.
- **How enemies work with the flash:** an enemy joins the group `"enemies"`, has a `take_hit(damage, push)` function, and can optionally have `is_alive()`. For the counter it also needs `is_counterable()` (true mid-lunge) and `cut_in_half(dir)`. The fruit minion has both. The player joins the group `"player"`.
- **The Big Pineapple boss, from the ENEMY session:** `code/design/fruit_boss.gd`, `boss_wave.gd`, `enemy_kit.gd` and `scene/design/fruit_boss.tscn`.
  - It summons Mango minions. The flash hits it, but the counter doesn't: it has no `is_counterable()`.
  - **Juggling is for bosses only** (Morgan's call; minions don't juggle). A hit that gets through the boss's armor launches it (`JUGGLED`). Armor-piercing means damage 3, or any hit while it's dizzy or already juggled, including the flash. It lands into `RECOVER`: it can still be hurt then, but not launched again.
  - Placeholder art sheets for the minion, the boss and the juice drop are in `scene/design/art/`.
  - **Gym layout, left to right:** BossArena (x -2816 to -1728), then a 112px gate at x=-1696 (double-jump it), then the minion arena, then the original gym. Start/WallLeft has moved to x=-2848.
- **Don't rename these; enemy code depends on them:**
  - **In `player.gd`:** `state`, `state_time`, `facing`, the `State` enum (its order too: new states go at the end), the `"player"` group, `_shake(strength, time)` and `_set_state()`.
  - **In `scene/player.tscn`:** the sprite node's name, `AnimatedSprite2D`, and the animations `IDLE`, `ATTACK_HEAVY_WINDUP`, `ATTACK_LIGHT_1`, `ATTACK_LIGHT_2` and `DASH_ATTACK_LIGHT`. The boss finisher (`code/design/boss_finisher.gd`) plays these directly.
  - **The boss finisher takes control of the player for about 3 seconds.** It pauses the player's physics (`set_physics_process(false)`) and moves the player itself. Anything added to the player's `_process` still runs during the finisher, so don't put movement or animation there.
  - **In `fruit_minion.gd`:** `PLAYER_HITS`, `PLAYER_BOX`, `PLAYER_PUSH`, `PLAYER_SAFE_TIME`, `_player_safe_until`, `respawn_time`, `state`, `state_time` and `State`.
- **`code/design/training_dummy.gd` and `scene/design/flash_test.tscn`:** placeholder dummies set up to test the flash: a row of three, one next to a pit, one next to a wall.
- **Fixes in `player.gd`, approved by BOOM:**
  - `_state_brake`: a quick double-tap that landed during the braking time was ignored.
  - `_state_land`: landing while holding a direction dropped you to walking speed.

## Open issues (for BOOM or undecided)
- **Animations cut off by the code's timers:**
  - `LAND` shows 1 of its 3 frames.
  - `DASH_ATTACK_LIGHT` shows 3 of 6.
  - `DASH_ATTACK_HEAVY_IMPACT` shows 3 of 6.
  - `ATTACK_HEAVY_SMASH` shows 2 of 3.
  - `ATTACK_LIGHT_1/2` loops back to its first frame briefly.
- **Attack animations are set to loop** (`loop = true`).
- **No real combat system yet:** the player has no hitboxes, health, getting hurt, knockback or death, and no hurt or death animations. The ENEMY session's fruit minion (`code/design/fruit_minion.gd`) uses stand-in hitboxes: the minion reads which attack the player is doing. It has a `take_hit(damage, push)` function. It was merged into the main folder on 2026-09-29, together with `code/design/juice_drop.gd` and `scene/design/fruit_minion.tscn`. The gym now has a minion arena at x -1664 to 0, left of the start point; Start and WallLeft moved to x=-1696. The flash kills a minion in one hit.
- **Letting go of the arrow in the air** stops you dead on landing. We offered a short slide instead; not done.
- **Undecided:** the tile size (16 or 32px, ask BOOM) and what juice does (heal, buff or score). Both shape the monster and level design.
- **Typo:** the project name in `project.godot` is "TropcalHunts".

## Next steps for Morgan
1. Play the gym and write down the level design rules.
2. Write a card for each monster: how it moves, its attack and the warning before it, which player attack beats it, what it drops, and the animations BOOM needs to make.
3. Level 1: sketch it on paper, then build it in Godot with plain blocks, using the gym measurements and plain boxes where monsters will go.

## Other Claude sessions
Other sessions may work in separate copies of the project under `.claude/worktrees/`. Their changes don't show in the game Morgan runs until they're merged into the main folder. Don't commit the `.claude/` folder.
Only one session should change `code/player.gd` at a time. Check with Morgan before editing it, or you'll get merge conflicts.
