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
5. **Work directly on `main`.** The team decided this on 2026-10-01, since Morgan writes most of the code; don't make feature branches. Still **don't commit or push without asking.**
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
- **Speeds:** walk 120 px/s. Run 260 after holding a direction for 0.5s. Sprint 420 after 1.4s. Gallop 600 after 2.5s (Morgan's call, 2026-10-04: half as long walking; these were 1s, 1.9s and 3s): speed level 4, BOOM's `GALLOP` animation, added 2026-09-29. `MOVE_STATES` maps each speed level to its state.
- **Player art:** BOOM's current sheet is `Sprite/PsV3.png`. It also has a one-frame `FLASH` animation that the code doesn't use yet.
- **Double-tap a direction:** run instantly, and sprint 0.5s later. While the DEBUG switch `debug_tap_gallop` in `player.gd` is on (it's on by default; ENEMY session, Morgan's call), a double-tap goes straight to full-speed gallop instead. Untick it on the Player in the Inspector for normal play. The logic is in `_double_tap_start()`.
- **Jump height:** about 103px. The double jump adds about 82px, for about 185px in total.
- **Full jump distance:** walking about 110px, running about 240px, sprinting about 385px.
- **Size:** the player is about 40px tall, and the node's origin is at the feet.
- **Hold W (the charged smash):** full charge after 0.35s (`CHARGE_TIME`; Morgan's call, 2026-10-04, was 1s). Keep holding and it goes off by itself 0.15s after full charge (`CHARGE_FULL_HOLD`; was 2s, Morgan's call), so a held W fires about 0.6s after the press. Letting go earlier fires a weaker one. The build-up sound starts partway into its file so its "ting" lands at full charge.
- **View limits:** at sprint speed you see only about 0.57s ahead. From 256px up, you can't see the ground.
- **Air attacks (added 2026-09-29):** Q in the air does the light combo with no lunge, keeping your drift, then goes back to falling. Landing in the middle of it cancels it into LAND (tracked by `light_in_air`, added by the ENEMY session). W in the air goes straight into `DASH_ATTACK_HEAVY_SLAM`: an immediate slam down with a big-shake impact, with no hop or hover (Morgan's call). The ground W wind-ups are also only 0.12s now (Morgan's call, done by the ENEMY session): `HEAVY_WINDUP_TIME` and `DASH_HEAVY_WINDUP_TIME` are 0.12, with `ANIM_SPEED_OVERRIDE` speeding up the wind-up animations to match. The standing W smashes almost at once, and the running W does a quick leap straight into the slam, with no hover. The sprint flash still only triggers on the ground.

## What we've added
- **`scene/design/gym_movement.tscn`:** a movement test room with ledges from 32 to 192px, a 1600px runway, gaps from 96 to 416px, low ceilings, a 256px drop, monster-size blocks and flying monster heights.
- **`code/live_reload.gd`:** a tool for development only. Add it as a Node in a scene. While the game runs, it reloads changed scripts and scenes from disk, keeps the position of the node named `Player`, and does nothing in exported builds.
- **The Thunderclap flash, in `player.gd`** (`_try_flash` and `_flash_strike`, settings in the `FLASH_*` constants). It's Morgan's idea, based on Zenitsu's move from *Demon Slayer*.
  - **Trigger:** only while galloping (speed level 4, Morgan's call, 2026-09-29), holding a direction, with an enemy up to 120px ahead. The flash happens instantly, with no pause (Morgan's call, 2026-09-29). It hits every enemy in its path and lands just past the last one, 160–240px away.
  - **Walls and pits:** it stops at walls and never lands over a pit.
  - **After:** the player comes out of it still galloping (also Morgan's call). There's no cooldown, so flashes can chain through groups of enemies.
  - **Visuals:** made in code: a yellow streak along the path, a spark burst where it lands, and screen shake. It has no state or animation of its own.
  - **You see the kills (the professor's idea, 2026-10-04):** `code/flash_finish.gd`. It's no longer a teleport.
    - **The dash:** with time stopped, you dash along the path (0.15s) leaving yellow afterimages and a lightning streak.
    - **Each enemy you pass:** you swing (the pose alternates), a slash appears across it, it flashes white, the Q sound plays, and the dash catches on it for 0.04s.
    - **The pose:** you hold it for 0.22s.
    - **The drop:** time restarts and they drop in order, 0.07s apart. Mangos split along their slash (`cut_in_half`), others take the flash's hit. You keep galloping.
    - **Slash lines are thin** (3px edge, 1px core; Morgan's call).
    - **Grass:** the path through the grass is cut via `cut_path()` on the living background.
    - **`flashing`:** `player.flashing` is true while those hits land (the tutorial's dummies report them as "FLASH").
    - **The player's code is paused during the freeze**, like the counter.
- **The counter** (`_try_counter` in `player.gd`, which spawns `code/counter_chain.gd`). Press Q while an enemy is mid-lunge within 160px (`COUNTER_RANGE`, was 96). It doesn't work once that lunge has already hit you (Morgan's call). The Mango now pounces from 140px on a slower, higher arc (`lunge_range` 140, `lunge_velocity` (190, -320), was 72 and (230, -170)), so you have about twice as long to counter it (Morgan's call, 2026-10-04). It's Morgan's design; the horizontal beam was removed.
  - **Time stop:** `Engine.time_scale` is 0, re-applied every frame because hit-freezes reset it. The world dims to indigo, while the player stays lit (z 35) with physics off.
  - **The cuts:** after 0.18s the lunging enemy is cut in half. It splits along the exact slash line the counter draws (`cut_in_half(dir, a, b)`, Morgan's call), and the top half slides off down the cut. Then the player teleports beside each other enemy with `cut_in_half()` that was on screen when the counter started, nearest first (leaving a teal afterimage and a streak), and cuts it too.
  - **Resume:** time restarts, every cut enemy falls apart at once, there's a big shake, and the player is protected for 0.6s.
  - **Safety:** if the node is removed mid-chain, `_exit_tree` always restores `time_scale`.
  - **Banner:** a pixel "COUNTER!" banner with a chain count (X2, X3…) is drawn by the combo HUD through `counter_start`, `counter_cut` and `counter_end`.
  - **Scope:** only enemies with `cut_in_half()` are chained, so the boss isn't. It works from any state except the heavy attacks.
- **How enemies work with the flash:** an enemy joins the group `"enemies"`, has a `take_hit(damage, push)` function, and can optionally have `is_alive()`. For the counter it also needs `is_counterable()` (true mid-lunge, until the lunge hits) and `cut_in_half(dir, a, b)` (split along the slash from a to b; both are optional). The fruit minion has both. The player joins the group `"player"`.
- **The Big Pineapple boss, from the ENEMY session:** `code/design/fruit_boss.gd`, `boss_wave.gd`, `enemy_kit.gd` and `scene/design/fruit_boss.tscn`.
  - It summons Mango minions. The flash hits it, but the counter doesn't: it has no `is_counterable()`.
  - **Juggling is for bosses only** (Morgan's call; minions don't juggle). A hit that gets through the boss's armor launches it (`JUGGLED`). Armor-piercing means damage 3, or any hit while it's dizzy or already juggled, including the flash. It lands into `RECOVER`: it can still be hurt then, but not launched again.
  - Placeholder art sheets for the minion, the boss and the juice drop are in `scene/design/art/`.
  - **Gym layout, left to right:** BossArena (x -2816 to -1728), then its entrance at x=-1696, then the minion arena, then the original gym. Start/WallLeft has moved to x=-2848.
  - **The entrance is a breakable portcullis** (`code/design/breakable_door.gd`, from the ENEMY session). A wall section above it leaves a 112px doorway.
    - **Breaking it:** any attack, a charged W in reach, or galloping into it.
    - **After:** it drops back down after 1s, waiting while anything is in the doorway, and calls `burst(pos, 3.0)` when it lands. It isn't in `"enemies"`.
    - **Background hook:** effects can shake the living background with `call_group("living_background", "burst", pos, strength)`.
    - **For other scenes:** it emits `shattered` when it breaks. `gallop_only` makes only galloping break it (the tutorial uses both).
- **Don't rename these; enemy code depends on them:**
  - **In `player.gd`:** `state`, `state_time`, `facing`, `flashing`, the `State` enum (its order too: new states go at the end; the newest is `KNOCKBACK`), the `"player"` group, `_shake(strength, time)`, `_set_state()`, `play_swing_sound()` (the boss air combo calls it) and `bounce_back()` (the boss calls it).
  - **In `scene/player.tscn`:** the sprite node's name, `AnimatedSprite2D`, and the animations `IDLE`, `ATTACK_HEAVY_WINDUP`, `ATTACK_LIGHT_1`, `ATTACK_LIGHT_2` and `DASH_ATTACK_LIGHT`. The boss finisher (`code/design/boss_finisher.gd`) plays these directly.
  - **The boss finisher takes control of the player for about 3 seconds.** It pauses the player's physics (`set_physics_process(false)`) and moves the player itself. Anything added to the player's `_process` still runs during the finisher, so don't put movement or animation there.
  - **In `fruit_minion.gd`:** `PLAYER_HITS`, `PLAYER_BOX`, `PLAYER_PUSH`, `PLAYER_SAFE_TIME`, `_player_safe_until`, `respawn_time`, `state`, `state_time` and `State`.
- **The combo counter, `code/combo_hud.gd`:** a CanvasLayer the player adds in `_ready`.
  - **Counting:** a hit is any enemy in `"enemies"` whose `hp` drops, so enemies need an `hp` value that goes down when hit.
  - **Timing:** the combo ends 2s (real time) after the last hit. The counter shows from the second hit.
  - **Ranks:** NICE at 5, GREAT at 10, JUICY! at 20, TROPICAL!! at 35 and FRESH SQUEEZED at 50 (cycles through the colors).
  - **Style:** BOOM's pixel-art style (Morgan's call). It's drawn at the game's own resolution with rects only, in his palette (the constants at the top), with a hand-made 5x7 pixel font (`GLYPHS`, only the letters the words need). Nothing is drawn behind the number (Morgan removed the crescent).
  - **Scripted hits:** moves can add hits directly with `get_tree().call_group("combo_hud", "add_hits", n)`, and end the combo with `call_group("combo_hud", "finish")`. `finish()` shows the full total at once, then ignores all hits until that combo has left the screen.
  - **The boss finisher** adds 4 hits per flurry slash (26 slashes, 104 hits) and calls `finish()` the moment the final cut starts, so the count stops there (Morgan's call).
- **The living background, `code/design/living_background.gd`:** the gym's "LivingBackground" node. Morgan asked for it through the ENEMY session, wanting a premium look with a wow factor. It's in BOOM's pixel style: flat colors with one shade each, opaque, greens from the fruit art and accents from BOOM's sheet.
  - **Background:** a sky (a CanvasLayer at -100), then six parallax layers that repeat every 960px, from far to near: drifting clouds, the volcano range, the far canopy, a row of distant trees, palms, and flowering bushes, with shimmering light shafts between the canopy and the trees. Each moves at its own speed (set in `_process`, 0.05 for the volcano up to 0.55 for the bushes); the prof asked for 5–6 layers. The scene's "Backdrop" is hidden at runtime.
  - **Grass and flowers** on every StaticBody2D top, except bodies named Wall*, Ceiling*, Monster* or PitBed.
    - Dense (Morgan's call): about one blade per pixel. Blades behind the player are 8–17px tall (z -2); 20% sit in front of the feet at 5–9px (z 2).
    - Only a barely-there breeze (Morgan's call): tips shift a pixel now and then. Grass really moves only when the player passes or a shockwave hits it. It parts from the feet and gets brushed in the running direction, up to about 12px at full speed. It's springy (low damping), so it swings for about a second after you pass.
    - Drawn as merged vertical strips to keep the frame cost down.
  - **Water** fills the open parts of "PitBed" tops, 24px deep, drawn in front of the player (z 2), with waves, splashes and wading.
  - **Shallow water (Morgan's call):**
    - **Where:** floors at least 480px long get about one 140–300px stretch per 900px, flooded 3px deep. The placement is seeded, so it's the same every run. It never overlaps a block and has no grass.
    - **Spray:** running through it throws spray up and behind, scaling with speed into a rooster tail at a gallop. Landing in it splashes, and reaching top speed in it bursts.
  - **W in water = a wave, not dust (Morgan's call):**
    - **The wave:** ATTACK_HEAVY_SMASH, DASH_ATTACK_HEAVY_IMPACT or CHARGED_SMASH with the feet in water rolls a curling wave both ways (`W_WAVES`: height, reach, damage = 18/150/2, 22/190/3, 30/260/4).
    - **Hits:** it stops at walls, and calls `take_hit` once per enemy (push 220 out, 220 up).
    - **No dust:** ENEMY's `movement_dust.gd` and `charge_fx.gd` skip W dust in water by asking `in_water(pos)` on the node in the `"living_background"` group.
  - **Leaves and pollen** drift around the camera.
  - **Reactions:** reaching the top speed level, LAND, ATTACK_HEAVY_SMASH, DASH_ATTACK_HEAVY_IMPACT, CHARGED_SMASH (the strongest) and every enemy hp drop send a shockwave ripple through the grass and leaves. A flash (a big jump in one frame) cuts a path through the grass.
- **The tutorial, `scene/design/tutorial.tscn` (added 2026-10-04):** every mechanic explained, then tested, one at a time.
  - **Stations, left to right:** MOVE, JUMP, DOUBLE JUMP, DOUBLE TAP, SLASH, SMASH, CHARGED SMASH, ROLLING SLASH, LEAP SLAM, AIR SLASH, AIR SLAM, COUNTER, THUNDERCLAP FLASH, FINAL TEST (3 Mangos that stay dead).
  - **How it works:** each station is a child of `Stations` and ends in a gate (`code/design/tutorial_gate.gd`, the portcullis art) that winches up when its test is passed. `code/design/tutorial.gd` (the "Director" node) decides what counts, from the player's state names. The steps and their hints are in `_make_steps()`. The game never waits for the HUD: a station counts from the moment you walk in, and its gate opens as soon as you pass, even if its card is still waiting to come in (for example, behind the TUTORIAL intro). The HUD catches up. If you walk into a station while the last one's stamp is still playing, its card skips the big centre entrance and goes straight to the top, so its pips are there right away (LEAP SLAM looked like it wasn't counting before this).
  - **The look (Morgan asked for premium animations):** `code/design/tutorial_hud.gd`, in BOOM's pixel style like the combo HUD. Each station's title slams in big, then flies to the top. Key caps rise into a band at the bottom and act out the presses, and they light up when the real key is pressed. Juice drops fly from the hit into progress pips, and a CLEAR stamp follows. Wrong moves get a tip. In the world: flags, bobbing arrows, and a "!" then a "Q / NOW!" over the counter Mango. A `Spot` marker (CHARGED SMASH) gets a glowing floor pad and a big arrow with STAND HERE (Morgan asked for it to be explicit). Both turn green and say NOW HOLD W while you stand on it, and that station hides its dummy arrows.
  - **`code/design/pixel_font.gd`:** the full 5x7 font (A-Z, 0-9, punctuation, arrows) and key caps. `{braces}` highlight words. Don't call a constant `Font` (it's a Godot class name); the scripts use `Pixel`.
  - **Dummies:** `code/design/tutorial_target.gd`. PLACEHOLDER sacks on posts, or hanging (`hanging = true`) for air attacks. They take hits like the minion (EnemyKit) and never die. A station with `"break"` set ends with `break_off(style)` on the dummy that took the last hit (Morgan's call). The pieces fly off spinning, bounce, then blink out; the stump stays.
    - **SLASH, `"cut"`:** one slanted cut under the sack, and the whole top flies off. Sound: the boss finisher's crash, quieter.
    - **SMASH, `"smash"`:** crushed flat for a moment, then the post snaps low and jagged, and the head, sack and a chunk of post fly apart with straw and dust. Sound: the boss's heavy impact.
    - **AIR SLASH, `"snap"`** (hanging dummies only): the cord snaps just above its head. The dummy flies off and the rest of the cord whips back up, frayed. The hanging dummy is a pendulum, so each hit swings it well out and it tilts along its rope (Morgan asked for a more visible swing). AIR SLASH clears in 2 hits.
  - **SMASH counts a held W (the charged smash) too** (Morgan's call).
  - **ROLLING SLASH needs one roll through both dummies** (Morgan's call). A roll that only catches one drains the pips and gives a tip.
  - **Testing one station:** move the Player in the scene; stations left of where it starts count as done. LiveReload keeps your place too.
  - **Double tap = gallop at once (Morgan's call):** the tutorial teaches the `debug_tap_gallop` behaviour as the real one. DOUBLE TAP's way out is the gym's breakable gate (`breakable_door.gd` with `gallop_only` on and `reseal_time` 0). Galloping through it, with the smash and slow-mo, clears the station (Morgan's call). SLASH after it is 1024px wide, so there's room to let go before its gate. There's no hold-to-build-up station, and no SKID STOP (removed, Morgan's call). Galloping into a wall anywhere shows a tip.
  - **Dummies ignore the flash except in THUNDERCLAP FLASH** (`flashable` on `tutorial_target.gd`), so galloping at them earlier doesn't set it off. They do it by answering `is_alive()` false while the player gallops; the flash skips enemies that aren't alive.
  - **Moves unlock at their station (Morgan's call):** no double jump before DOUBLE JUMP, and no gallop before DOUBLE TAP. Until then, holding a direction or double-tapping tops out at the sprint. `_apply_locks()` in `tutorial.gd` does this by holding down `air_jumps_left` and `hold_time` each frame, so `player.gd` is untouched.
  - **MOVE and JUMP clear once you get to their flag or past it, at any speed or height** (their Goals have `metadata/pass`; Morgan's call). You can jump right over JUMP's flag.
  - **JUMP has one 64px step and one flag:** a tapped jump falls short, a held one makes it.
  - **Combat station floors are 448px wide** so the living background puts no shallow water in them (W in water makes a wave, not the smash being taught).
- **`code/design/training_dummy.gd` and `scene/design/flash_test.tscn`:** placeholder dummies set up to test the flash: a row of three, one next to a pit, one next to a wall.
- **Fixes in `player.gd`, approved by BOOM:**
  - `_state_brake`: a quick double-tap that landed during the braking time was ignored.
  - `_state_land`: landing while holding a direction dropped you to walking speed.
- **Sound (added 2026-10-01).** Files are in `sounds/` (attributions in `sounds/credits.rtf`). Each sound is a constant at the top of the script that plays it, with its own `_DB` volume and often a `_SKIP` (seconds of silence at the start of the file to skip, so it lands on the action).
  - **Player (`player.gd`):** Q/W swings (`play_swing_sound`, also used by the boss air combo), wall clang when a swing reaches a wall, footsteps on frames 0 and 2 of WALK/RUN/SPRINT/GALLOP (a splash in water), jumps (`sounds/jump/jump_snow.wav`, the double jump is the same sound pitched up), the W charge build-up, and the gallop wall impact.
  - **Elsewhere:** gallop start (`sound_barrier.gd`), gate break (`breakable_door.gd`, the Matrix sound sped up to the 1.2 s slow motion), minion damage and kill (`fruit_minion.gd`), boss armor clang, damage squelch, roll rumble and impacts (`fruit_boss.gd`), finisher slashes and final crash (`boss_finisher.gd`), counter cuts (`counter_chain.gd`), W waves (`living_background.gd`).
  - **Laptop speakers:** Morgan tests on speakers that barely play anything under ~300 Hz. Sounds made of deep bass come out faint however loud the file is. Measure loudness with a 300 Hz high-pass, not only RMS.
  - **Morgan's taste:** made-in-code sounds read as "too video game" except plain ones like the footsteps. Prefer cutting his recordings; when generating, keep it simple.
- **Feel (added 2026-10-01):**
  - **Hold Q** keeps the light combo going.
  - **Armor pushback:** a melee hit that bounces off the boss's armor knocks the player back (`bounce_back()` in `player.gd`).
  - **Knockback:** galloping into a wall puts the player in `KNOCKBACK` (added at the end of the `State` enum): squashed against the wall, thrown back in an arc, dazed with stars. PLACEHOLDER art made in code from BOOM's BRAKE, DOUBLE_JUMP and LAND frames (`_add_knockback_anim`, added at runtime; `player.tscn` is untouched). BOOM needs to draw a real KNOCKBACK.
  - **Finisher mashing (the professor's ask):** the million-cut flurry only advances while Q/W is mashed (2 slashes per press). Stop and the player slowly falls; after 1.5 s it cancels and the boss is back to full health (`finisher_failed()`). The finisher's combo total is fixed: 26 slashes x 4 hits.
  - **Juice spray (`code/design/juice_spray.gd`):** every hit that damages the boss sprays juice out the far side (jet, droplets that splat, chunks, mist). Finisher slashes spray any direction, and the boss explodes in 14 bursts when it falls apart (`explode_juice()`). PLACEHOLDER.

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
**Watch out for the Godot editor overwriting files.** If Morgan's editor has a script open with an old copy, pressing Cmd+R saves it back over newer changes on disk. This happened to `player.gd` on 2026-09-29. After editing a file, check your edit is still there if something seems off, and remind Morgan to choose "Reload" when Godot says files changed on disk.
