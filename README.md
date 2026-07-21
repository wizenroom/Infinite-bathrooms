# gmtk-terragen — "OCCUPIED" prototype

GMTK game jam entry built in **Godot 4** (GDScript, 3D top-down).

**The pitch:** you really need to go. The bathroom is infinite. Every stall is
occupied except one. Knock on doors, fight whatever answers, find the free
stall before the urgency meter fills.

## Play it

1. Open the project in Godot 4.6+ (Project Manager > Import > `project.godot`).
2. Press F5.

| Input | Action |
| --- | --- |
| WASD | Move |
| Mouse | Look (first person) |
| LMB / Space | Melee swing |
| E | Knock on the stall you're facing |
| Esc | Release mouse |
| R | Restart (after win/lose) |

Reading the bathroom: **red indicator light** usually means a hostile occupant,
**feet under the door** almost always do, and ~15% of indicators lie. Knocking
can also find loot (plunger upgrade, urgency relief), friendly NPCs, or the one
free stall — which is guarded.

## Project layout

```
scenes/
  prototype.tscn         Main scene (everything is built in code from here)
  main.tscn              Old terrain demo, kept for reference
scripts/proto/
  bathroom.gd            Manager: corridor generation, knock outcomes, HUD, win/lose
  stall.gd               Stall geometry, door, indicator/feet signals
  player.gd              Movement, mouse aim, melee, urgency meter
  enemy.gd               Chase / telegraph / lunge melee AI
scripts/
  terrain_generator.gd   (old demo) heightmap terrain
  object_spawner.gd      (old demo) surface spawner
```

## Tuning knobs

- Outcome weights (`W_HOSTILE` etc.) and free-stall depth: top of `bathroom.gd`
- Urgency rates, speeds, attack stats: top of `player.gd`
- Enemy aggression and timing: top of `enemy.gd`
- Signal honesty (lying indicators, feet visibility): `stall.gd`
