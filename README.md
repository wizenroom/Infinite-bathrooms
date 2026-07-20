# gmtk-terragen

GMTK game jam entry built in **Godot 4.4** (GDScript, 3D). The core idea:
procedural terrain generation with objects spawned on the generated surface.

## Getting started

1. Open the project in Godot 4.4+ (Project Manager > Import > select `project.godot`).
2. Press F5 to run. You'll see noise-generated terrain with placeholder boxes spawned on it.
3. Press **R** in-game to regenerate the terrain with a new seed.

## Project layout

```
scenes/
  main.tscn            Main scene: terrain, spawner, camera, light, sky
scripts/
  terrain_generator.gd Heightmap terrain (mesh + trimesh collision) from FastNoiseLite
  object_spawner.gd    Spawns objects on the terrain surface after generation
  main.gd              Input handling (R = regenerate)
```

## Where to plug in your own generation

- `TerrainGenerator.get_height(x, z)` is the single source of truth for terrain
  height. Replace its noise lookup with your own algorithm (wave function
  collapse, erosion simulation, etc.) and the mesh, collision, and spawning all
  follow automatically.
- `ObjectSpawner.spawn_scene` — assign any `PackedScene` in the inspector to
  spawn real objects instead of placeholder boxes.
- `ObjectSpawner.random_surface_point` sampling can be swapped for
  density-based or rule-based placement.
