# Godat: 5-day plan (2026-10-20 to 2026-10-24)

Turn-based grid roguelike. You act, then every enemy acts once in order.
Every level-up pauses the game and offers 3 cards (passives or active skills).

## Day 1 (Tue 20th): core loop ✅
- Grid dungeon (drunkard's walk), player move / bump-attack / wait
- Enemies chase with A* and attack in turn order
- XP, levels, 3-card pick screen, 6 passives + 3 skills
- Floor clears -> stairs -> deeper floor with tougher enemies

## Day 2 (Wed 21st): content and feel
- ✅ Card rarity (common/rare/epic), 16 cards total incl. Stone Skin and Chain Lightning skills
- ✅ New enemies: Bat (moves twice), Archer (shoots in straight lines), Brute (slow, hits hard)
- ✅ Floating damage numbers, attack lunge, projectile/spell lines
- Art: swap coloured squares for a CC0 tileset (e.g. Kenney 1-bit pack)
- Enemy variety: ranged attacker, slow heavy hitter, fast double-mover
- Card rarity (common/rare/epic) and 6-10 more cards, incl. synergies
- Hit/move animations, damage numbers, basic sound effects

## Day 3 (Thu 22nd): dungeon and progression
- Rooms + corridors generation, field of view / fog of war
- Boss floor every 3 depths, pickups (potions, gold)
- Win condition (e.g. beat the depth-9 boss)

## Day 4 (Fri 23rd): UI and balance
- Title screen, pause menu, run summary on death/win
- Balance pass (XP curve, enemy scaling, card numbers) using tools/sim.gd
- Best-run high score saved to disk

## Day 5 (Sat 24th): polish and ship
- Playtest + bug fixing, screen shake / juice
- Export Windows + Web builds, itch.io page
