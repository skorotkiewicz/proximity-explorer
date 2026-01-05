# Proximity Explorer

> *A multiplayer exploration game where connection happens within range.*

![Proximity Explorer](docs/game.png)

---

## Overview

**Proximity Explorer** is a real-time multiplayer game built on the [Cleoselene](https://cleoselene.com/) engine. Players explore a procedurally generated world where interaction is limited by physical proximity—you can only see and chat with players within 100 pixels of your position.

## Features

- **Seeded World Generation** — Deterministic terrain using a fixed seed. Position `(100, 753)` always produces the same landscape.
- **Proximity Visibility** — Players fade into view as they approach (100px range)
- **Local Chat** — Messages are only visible to nearby players
- **Tile-Based Terrain** — Water, rocks, trees, grass, and sand with distinct passability rules

## Controls

| Key | Action |
|-----|--------|
| `W` `A` `S` `D` or `↑` `←` `↓` `→` | Move |
| `Enter` | Open chat |
| `Esc` | Cancel chat |

## Running

```bash
cleoselene proximity_game.lua
```

Then open your browser to the displayed URL.

## Configuration

Edit `proximity_game.lua` to customize:

```lua
CONFIG = {
    VISIBILITY_RANGE = 100,  -- Player detection radius
    CHAT_RANGE = 100,        -- Chat message visibility
    PLAYER_SPEED = 150,      -- Movement speed (px/sec)
    WORLD_WIDTH = 2000,      -- World dimensions
    WORLD_HEIGHT = 2000,
    TILE_SIZE = 32,          -- Terrain tile size
    SEED_OFFSET = 12345,     -- World generation seed
}
```

## How It Works

1. **Connect** — Each player joins with a unique session and spawns near `(100, 753)`
2. **Explore** — Navigate the procedurally generated terrain
3. **Discover** — When another player enters your visibility range, they fade into view
4. **Communicate** — Chat messages only reach players within range

---

<p align="center">
  <em>Built with Cleoselene — Multiplayer-First Game Engine</em>
</p>
