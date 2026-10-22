# Art

Drop 32x32 PNGs here and they are picked up automatically by name.
Anything without a file is drawn as a coloured square with a letter.

| File | Used for |
|------|----------|
| `player.png` | the player |
| `floor.png`, `wall.png`, `stairs.png` | map tiles (stairs is drawn on top of the floor, so transparency works) |
| `floor_3.png`, `wall_3.png`, `stairs_3.png`, ... | map tiles from that depth on, until the next numbered one (e.g. `wall_1` + `wall_4` = one look for depths 1-3, another for 4+) |
| `rat.png`, `bat.png`, `goblin.png`, `archer.png`, `orc.png`, `brute.png`, `wraith.png` | enemies (name from `KINDS` in `scripts/enemy.gd`, lowercase) |

The HP bar is drawn over the bottom 5 pixels, so keep important detail above that.
Pixel art stays crisp: the project uses nearest-neighbour filtering.
