# Godat

Turn-based roguelike prototype in Godot 4.5+ (GDScript, tested on 4.7). See PLAN.md for the 5-day plan.

## Run
Open `project.godot` in Godot 4.5+ and press F5.

## Controls
- Arrows / WASD: move, or attack by moving into an enemy
- Space or `.`: wait a turn
- 1-3: use skills
- On level-up: click a card or press 1-3
- R after death: restart

## Code map
- `scripts/main.gd`: dungeon generation, turn loop, combat, skills, HUD
- `scripts/unit.gd`: shared grid unit (HP, drawing, damage)
- `scripts/player.gd`: XP/levels and card-modified stats
- `scripts/enemy.gd`: enemy kinds (`KINDS`) and depth scaling
- `scripts/cards.gd`: the card pool (`POOL`), offer rules and effects
- `scripts/level_up_ui.gd`: the 3-card pick overlay
- `tools/sim.gd`: headless bot that plays random turns, for smoke tests/balance:
  `godot --headless --script res://tools/sim.gd`
- `tools/feature_test.gd`: headless check that applies every card and fires every skill on a depth-3 floor
