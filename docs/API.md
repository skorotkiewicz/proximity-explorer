# Cleoselene API Reference
> https://cleoselene.com/

## Overview

A Multiplayer-First Server-Rendered Game Engine with Lua Scripting.

### Get Started

Run:

```
cleoselene my_game.lua
```

## API Reference
### Display & Coordinates

The engine uses a fixed virtual coordinate system of 800x600. All drawing commands (api.fill_rect, api.draw_line, etc.) use these coordinates. The engine automatically scales the output to fit the user's screen while maintaining the logical resolution and aspect ratio.

### Graphics & Sound

Method 	Description
api.clear_screen(r, g, b) 	Clears the frame with a background color.
api.set_color(r, g, b, [a]) 	Sets the current drawing color.
api.fill_rect(x, y, w, h) 	Draws a filled rectangle.
api.draw_line(x1, y1, x2, y2, [width]) 	Draws a line.
api.draw_text(text, x, y) 	Draws text at position.
api.load_sound(name, url) 	Preloads a sound from a URL/path (relative to script).
api.play_sound(name, [loop]) 	Plays a loaded sound.
api.stop_sound(name) 	Stops a sound.
api.set_volume(name, volume) 	Sets volume (0.0 to 1.0).

### Spatial DB (Geometry)

The engine provides a high-performance Spatial Hash Grid for broadphase queries.

### Creation

local db = api.new_spatial_db(cell_size) -- e.g., 250

### Object Management

Method 	Description 	Returns
db:add_circle(x, y, radius, tag) 	Registers a circular entity. 	id (int)
db:add_segment(x1, y1, x2, y2, tag) 	Registers a line segment (wall). 	id (int)
db:remove(id) 	Removes an entity from the DB. 	nil
db:update(id, x, y) 	Manually updates position (teleport). 	nil
db:get_position(id) 	Returns x, y of the entity. 	x, y
Queries (Sensors)
Method 	Description 	Returns
db:query_range(x, y, r, [tag]) 	Finds entity IDs within radius r. 	{id1, id2...}
db:query_rect(x1, y1, x2, y2, [tag]) 	Finds entity IDs within AABB (Culling). 	{id1, id2...}
db:cast_ray(x, y, angle, dist, [tag]) 	Casts a ray. 	id, frac, hit_x, hit_y or nil

### Physics Engine (Simulation)

Handles rigid body dynamics, integration, and collision resolution.

### Creation

local phys = api.new_physics_world(db)

### Body Management

Method 	Description
phys:add_body(id, props) 	Adds physics to an entity. Props: {mass=1.0, restitution=0.5, drag=0.0}.
phys:set_velocity(id, vx, vy) 	Sets velocity.
phys:get_velocity(id) 	Returns vx, vy.
phys:set_gravity(x, y) 	Sets global gravity vector.
phys:step(dt) 	Advances simulation. Resolves collisions and updates db.
phys:get_collision_events() 	Returns list of collisions since last step: {{idA, idB}, ...}.

### Graph Navigation (Pathfinding)

Native A* implementation on a custom graph.
Method 	Description
nav = api.new_graph() 	Creates a new navigation graph.
nav:add_node(id, x, y) 	Adds a node to the graph.
nav:add_edge(u, v) 	Adds an edge (connection) between nodes.
nav:find_path(start, end) 	Returns a list of node IDs forming the shortest path.