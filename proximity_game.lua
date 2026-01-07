-- ============================================================================
-- PROXIMITY EXPLORER - A Multiplayer Exploration Game
-- ============================================================================
-- Features:
--   - Seeded procedural map generation
--   - Limited visibility (100px range)
--   - Proximity-based player interaction and chat
--   - Real-time multiplayer movement
-- ============================================================================

-- Configuration
local CONFIG = {
    SCREEN_WIDTH = 800,         -- Screen width (800x600 virtual resolution)
    SCREEN_HEIGHT = 600,        -- Screen height
    VISIBILITY_RANGE = 100,     -- Max pixels players can see each other
    CHAT_RANGE = 100,           -- Max pixels for chat visibility
    PLAYER_SPEED = 150,         -- Pixels per second
    PLAYER_SIZE = 8,            -- Player circle radius
    WORLD_WIDTH = 2000,         -- Total world width
    WORLD_HEIGHT = 2000,        -- Total world height
    TILE_SIZE = 32,             -- Size of each map tile
    SEED_OFFSET = 77777,        -- Base seed for generation
    CHAT_DURATION = 5,          -- Seconds chat messages stay visible
    MAX_CHAT_HISTORY = 10,      -- Max chat messages per player
}

-- Game state
local db = nil
local players = {}
local usernames = {}  -- Track taken usernames for uniqueness
local world_tiles = {}  -- Cache for generated tiles
local game_time = 0     -- Track game time manually

-- ============================================================================
-- IMPROVED SEEDED TERRAIN GENERATOR
-- Uses multi-octave fractal noise for natural-looking landscapes
-- ============================================================================

-- Simple hash function for deterministic randomness
local function hash(x, y, seed)
    local n = (x * 374761393 + y * 668265263 + seed * 1013904223) % 2147483647
    n = ((n * 1103515245 + 12345) % 2147483647)
    n = ((n * 1103515245 + 12345) % 2147483647)
    return (n % 10000) / 10000
end

-- Smoothstep for interpolation
local function smoothstep(t)
    return t * t * (3 - 2 * t)
end

-- 2D gradient noise (simplified Perlin-like)
local function gradient_noise(x, y, seed)
    -- Get integer grid coordinates
    local x0 = math.floor(x)
    local y0 = math.floor(y)
    local x1 = x0 + 1
    local y1 = y0 + 1
    
    -- Fractional parts
    local fx = x - x0
    local fy = y - y0
    
    -- Smooth the fractional parts
    local sx = smoothstep(fx)
    local sy = smoothstep(fy)
    
    -- Hash values at grid corners
    local n00 = hash(x0, y0, seed)
    local n10 = hash(x1, y0, seed)
    local n01 = hash(x0, y1, seed)
    local n11 = hash(x1, y1, seed)
    
    -- Bilinear interpolation
    local nx0 = n00 + sx * (n10 - n00)
    local nx1 = n01 + sx * (n11 - n01)
    
    return nx0 + sy * (nx1 - nx0)
end

-- Multi-octave fractal noise (fBm - Fractal Brownian Motion)
local function fractal_noise(x, y, seed, octaves, persistence, scale)
    local value = 0
    local amplitude = 1
    local frequency = 1 / scale
    local max_value = 0
    
    for i = 1, octaves do
        value = value + gradient_noise(x * frequency, y * frequency, seed + i * 1000) * amplitude
        max_value = max_value + amplitude
        amplitude = amplitude * persistence
        frequency = frequency * 2
    end
    
    return value / max_value
end

-- Get terrain type based on elevation and moisture
local function get_tile_type(world_x, world_y)
    local tile_x = math.floor(world_x / CONFIG.TILE_SIZE)
    local tile_y = math.floor(world_y / CONFIG.TILE_SIZE)
    local key = tile_x .. "," .. tile_y
    
    -- Check cache first
    if world_tiles[key] ~= nil then
        return world_tiles[key]
    end
    
    -- Generate elevation map (large scale terrain features)
    local elevation = fractal_noise(tile_x, tile_y, CONFIG.SEED_OFFSET, 4, 0.5, 30)
    
    -- Generate moisture map (for biome variation)
    local moisture = fractal_noise(tile_x, tile_y, CONFIG.SEED_OFFSET + 5000, 3, 0.6, 40)
    
    -- Add some local detail noise
    local detail = fractal_noise(tile_x, tile_y, CONFIG.SEED_OFFSET + 10000, 2, 0.5, 8) * 0.15
    elevation = elevation + detail
    
    -- Determine tile type based on elevation and moisture
    local tile_type
    
    if elevation < 0.30 then
        -- Low elevation = water
        tile_type = "water"
    elseif elevation < 0.35 then
        -- Beach/shore
        tile_type = "sand"
    elseif elevation < 0.65 then
        -- Mid elevation - depends on moisture
        if moisture < 0.35 then
            tile_type = "sand"      -- Dry = desert/sand
        elseif moisture < 0.55 then
            tile_type = "grass"     -- Medium = grassland
        else
            tile_type = "tree"      -- Wet = forest
        end
    elseif elevation < 0.78 then
        -- Higher elevation
        if moisture > 0.5 then
            tile_type = "tree"      -- Wet highlands = dense forest
        else
            tile_type = "grass"     -- Dry highlands = meadow
        end
    else
        -- Mountain peaks
        tile_type = "rock"
    end
    
    -- Add some random scattered features (rare)
    local scatter = hash(tile_x * 7, tile_y * 11, CONFIG.SEED_OFFSET + 20000)
    if scatter > 0.97 and tile_type == "grass" then
        tile_type = "tree"  -- Occasional lone tree
    elseif scatter > 0.985 and tile_type == "grass" then
        tile_type = "rock"  -- Occasional boulder
    end
    
    -- Cache it
    world_tiles[key] = tile_type
    return tile_type
end

local function is_tile_passable(world_x, world_y)
    local tile = get_tile_type(world_x, world_y)
    return tile ~= "water" and tile ~= "rock" and tile ~= "tree"
end

-- ============================================================================
-- TILE COLORS (enhanced with slight variations)
-- ============================================================================
local TILE_COLORS = {
    water = {35, 95, 160},
    rock = {90, 85, 80},
    tree = {25, 85, 35},
    grass = {55, 130, 55},
    sand = {180, 160, 100},
}

-- ============================================================================
-- PLAYER COLORS (Unique per player based on hash)
-- ============================================================================
local function get_player_color(session_id)
    local h = 0
    for i = 1, #session_id do
        h = h + string.byte(session_id, i) * (i * 31)
    end
    
    -- Generate vibrant HSV-like color
    local hue = (h % 360) / 360
    local r = math.floor(math.abs(math.sin(hue * 6.28) * 200 + 55))
    local g = math.floor(math.abs(math.sin((hue + 0.33) * 6.28) * 200 + 55))
    local b = math.floor(math.abs(math.sin((hue + 0.66) * 6.28) * 200 + 55))
    
    return {r, g, b}
end

-- ============================================================================
-- DISTANCE CALCULATION
-- ============================================================================
local function distance(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

-- ============================================================================
-- SIMPLE SEEDED RANDOM FOR SPAWNING
-- ============================================================================
local rng_state = 12345

local function simple_random(min_val, max_val)
    rng_state = (rng_state * 1103515245 + 12345) % 2147483648
    local range = max_val - min_val + 1
    return min_val + (rng_state % range)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
function init()
    db = api.new_spatial_db(CONFIG.VISIBILITY_RANGE)
    game_time = 0
    print("Proximity Explorer initialized!")
    print("World size: " .. CONFIG.WORLD_WIDTH .. "x" .. CONFIG.WORLD_HEIGHT)
    print("Visibility range: " .. CONFIG.VISIBILITY_RANGE .. "px")
end

-- ============================================================================
-- UPDATE LOOP
-- ============================================================================
function update(dt)
    game_time = game_time + dt
    
    -- Update all players
    for session_id, player in pairs(players) do
        local inputs = player.inputs
        local vx, vy = 0, 0
        
        -- Handle movement input (arrow keys)
        if inputs[37] then vx = vx - 1 end  -- Left
        if inputs[39] then vx = vx + 1 end  -- Right
        if inputs[38] then vy = vy - 1 end  -- Up
        if inputs[40] then vy = vy + 1 end  -- Down
        
        -- WASD alternative
        if inputs[65] then vx = vx - 1 end  -- A
        if inputs[68] then vx = vx + 1 end  -- D
        if inputs[87] then vy = vy - 1 end  -- W
        if inputs[83] then vy = vy + 1 end  -- S
        
        -- Normalize diagonal movement
        if vx ~= 0 and vy ~= 0 then
            local len = math.sqrt(vx * vx + vy * vy)
            vx = vx / len
            vy = vy / len
        end
        
        -- Get current tile for speed modifier
        local current_tile = get_tile_type(player.x, player.y)
        local speed_modifier = 1.0
        if current_tile == "sand" then
            speed_modifier = 0.6  -- 40% slower on sand
        end
        
        -- Calculate new position
        local speed = CONFIG.PLAYER_SPEED * speed_modifier * dt
        local new_x = player.x + vx * speed
        local new_y = player.y + vy * speed
        
        -- Clamp to world bounds
        new_x = math.max(CONFIG.PLAYER_SIZE, math.min(CONFIG.WORLD_WIDTH - CONFIG.PLAYER_SIZE, new_x))
        new_y = math.max(CONFIG.PLAYER_SIZE, math.min(CONFIG.WORLD_HEIGHT - CONFIG.PLAYER_SIZE, new_y))
        
        -- Check collision with terrain
        if is_tile_passable(new_x, new_y) then
            player.x = new_x
            player.y = new_y
            db:update(player.entity_id, new_x, new_y)
        end
    end
    
    -- Clean up old chat messages
    for session_id, player in pairs(players) do
        local new_messages = {}
        for _, msg in ipairs(player.chat_messages) do
            if game_time - msg.time < CONFIG.CHAT_DURATION then
                table.insert(new_messages, msg)
            end
        end
        player.chat_messages = new_messages
    end
end

-- ============================================================================
-- DRAW FUNCTION (Called per client)
-- ============================================================================
function draw(session_id)
    local player = players[session_id]
    if not player then
        -- Draw loading screen for new players
        api.clear_screen(10, 10, 20)
        api.set_color(255, 255, 255)
        api.draw_text("Loading...", 380, 290)
        return
    end
    
    -- Draw username entry screen
    if player.entering_name then
        api.clear_screen(15, 20, 35)
        
        -- Title
        api.set_color(100, 200, 255)
        api.draw_text("PROXIMITY EXPLORER", 250, 190)
        
        -- Subtitle
        api.set_color(150, 150, 180)
        api.draw_text("Enter your username to join", 250, 220)
        
        -- Input box background
        api.set_color(30, 35, 50)
        api.fill_rect(250, 250, 300, 40)
        
        -- Input box border
        api.set_color(80, 120, 180)
        api.draw_line(250, 250, 550, 250, 2)  -- Top
        api.draw_line(250, 290, 550, 290, 2)  -- Bottom
        api.draw_line(250, 250, 250, 290, 2)  -- Left
        api.draw_line(550, 250, 550, 290, 2)  -- Right
        
        -- Username input
        api.set_color(255, 255, 255)
        api.draw_text(player.name_buffer .. "_", 260, 270)
        
        -- Error message
        if player.name_error then
            api.set_color(255, 100, 100)
            api.draw_text(player.name_error, 300, 310)
        end
        
        -- Instructions
        api.set_color(120, 120, 140)
        api.draw_text("2-16 characters (a-z, 0-9, _)", 270, 320)
        api.draw_text("Press ENTER to join", 300, 345)
        
        return
    end
    
    local px, py = player.x, player.y
    
    -- Calculate camera position (center on player)
    local cam_x = px - 400  -- Center camera on player (800/2)
    local cam_y = py - 300  -- Center camera on player (600/2)
    
    -- Clamp camera to world bounds (prevent showing empty space)
    cam_x = math.max(0, math.min(CONFIG.WORLD_WIDTH - 800, cam_x))
    cam_y = math.max(0, math.min(CONFIG.WORLD_HEIGHT - 600, cam_y))
    
    -- Calculate player's screen position (may not be center if near edge)
    local player_screen_x = px - cam_x
    local player_screen_y = py - cam_y
    
    -- Clear with dark background
    api.clear_screen(15, 20, 25)
    
    -- Draw visible tiles
    local start_tile_x = math.floor((cam_x - CONFIG.TILE_SIZE) / CONFIG.TILE_SIZE)
    local start_tile_y = math.floor((cam_y - CONFIG.TILE_SIZE) / CONFIG.TILE_SIZE)
    local end_tile_x = math.ceil((cam_x + 800 + CONFIG.TILE_SIZE) / CONFIG.TILE_SIZE)
    local end_tile_y = math.ceil((cam_y + 600 + CONFIG.TILE_SIZE) / CONFIG.TILE_SIZE)
    
    for tile_x = start_tile_x, end_tile_x do
        for tile_y = start_tile_y, end_tile_y do
            local world_x = tile_x * CONFIG.TILE_SIZE
            local world_y = tile_y * CONFIG.TILE_SIZE
            local screen_x = world_x - cam_x
            local screen_y = world_y - cam_y
            
            -- Only draw if on screen
            if screen_x > -CONFIG.TILE_SIZE and screen_x < 800 and
               screen_y > -CONFIG.TILE_SIZE and screen_y < 600 then
                local tile_type = get_tile_type(world_x, world_y)
                local color = TILE_COLORS[tile_type]
                
                -- Apply visibility fog (darker tiles further from player)
                local dist = distance(px, py, world_x + CONFIG.TILE_SIZE/2, world_y + CONFIG.TILE_SIZE/2)
                local fog = math.max(0.3, 1 - (dist / 400))
                
                api.set_color(
                    math.floor(color[1] * fog),
                    math.floor(color[2] * fog),
                    math.floor(color[3] * fog)
                )
                api.fill_rect(screen_x, screen_y, CONFIG.TILE_SIZE, CONFIG.TILE_SIZE)
            end
        end
    end
    
    -- Draw grid lines (subtle)
    api.set_color(40, 45, 50)
    for tile_x = start_tile_x, end_tile_x do
        local screen_x = tile_x * CONFIG.TILE_SIZE - cam_x
        if screen_x >= 0 and screen_x <= 800 then
            api.draw_line(screen_x, 0, screen_x, 600, 1)
        end
    end
    for tile_y = start_tile_y, end_tile_y do
        local screen_y = tile_y * CONFIG.TILE_SIZE - cam_y
        if screen_y >= 0 and screen_y <= 600 then
            api.draw_line(0, screen_y, 800, screen_y, 1)
        end
    end
    
    -- Draw visibility range indicator (subtle circle)
    api.set_color(255, 255, 255, 30)
    local segments = 32
    for i = 0, segments - 1 do
        local angle1 = (i / segments) * 2 * math.pi
        local angle2 = ((i + 1) / segments) * 2 * math.pi
        local x1 = player_screen_x + math.cos(angle1) * CONFIG.VISIBILITY_RANGE
        local y1 = player_screen_y + math.sin(angle1) * CONFIG.VISIBILITY_RANGE
        local x2 = player_screen_x + math.cos(angle2) * CONFIG.VISIBILITY_RANGE
        local y2 = player_screen_y + math.sin(angle2) * CONFIG.VISIBILITY_RANGE
        api.draw_line(x1, y1, x2, y2, 1)
    end
    
    -- Find nearby players within visibility range
    local nearby = db:query_range(px, py, CONFIG.VISIBILITY_RANGE, "player")
    
    -- Draw other players (only if in range)
    for _, entity_id in ipairs(nearby) do
        for other_id, other_player in pairs(players) do
            if other_player.entity_id == entity_id and other_id ~= session_id then
                local dist = distance(px, py, other_player.x, other_player.y)
                
                if dist <= CONFIG.VISIBILITY_RANGE then
                    local screen_x = other_player.x - cam_x
                    local screen_y = other_player.y - cam_y
                    
                    -- Calculate visibility alpha (fade out near edge of range)
                    local alpha = math.max(0, 1 - (dist / CONFIG.VISIBILITY_RANGE))
                    alpha = alpha * alpha  -- Quadratic falloff for smoother fade
                    
                    local color = get_player_color(other_id)
                    
                    -- Draw player glow
                    api.set_color(
                        math.floor(color[1] * 0.5),
                        math.floor(color[2] * 0.5),
                        math.floor(color[3] * 0.5),
                        math.floor(alpha * 100)
                    )
                    local glow_size = CONFIG.PLAYER_SIZE + 4
                    api.fill_rect(screen_x - glow_size, screen_y - glow_size, glow_size * 2, glow_size * 2)
                    
                    -- Draw player body
                    api.set_color(
                        math.floor(color[1] * alpha + 30 * (1 - alpha)),
                        math.floor(color[2] * alpha + 30 * (1 - alpha)),
                        math.floor(color[3] * alpha + 30 * (1 - alpha))
                    )
                    api.fill_rect(screen_x - CONFIG.PLAYER_SIZE, screen_y - CONFIG.PLAYER_SIZE, 
                                  CONFIG.PLAYER_SIZE * 2, CONFIG.PLAYER_SIZE * 2)
                    
                    -- Draw player inner
                    api.set_color(
                        math.min(255, math.floor(color[1] * 1.3)),
                        math.min(255, math.floor(color[2] * 1.3)),
                        math.min(255, math.floor(color[3] * 1.3))
                    )
                    local inner = CONFIG.PLAYER_SIZE - 3
                    api.fill_rect(screen_x - inner, screen_y - inner, inner * 2, inner * 2)
                    
                    -- Draw player name
                    if alpha > 0.3 then
                        api.set_color(255, 255, 255)
                        local name = other_player.name or ("Player " .. string.sub(other_id, 1, 4))
                        api.draw_text(name, screen_x - 20, screen_y - 22)
                    end
                    
                    -- Draw their recent chat messages (if in chat range)
                    if dist <= CONFIG.CHAT_RANGE and alpha > 0.3 then
                        local msg_y = screen_y - 38
                        for i = #other_player.chat_messages, math.max(1, #other_player.chat_messages - 2), -1 do
                            local msg = other_player.chat_messages[i]
                            if msg then
                                api.set_color(255, 255, 200)
                                api.draw_text(msg.text, screen_x - 30, msg_y)
                                msg_y = msg_y - 12
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Draw current player (always visible, at calculated screen position)
    local my_color = get_player_color(session_id)
    
    -- Player glow
    api.set_color(my_color[1], my_color[2], my_color[3], 80)
    local glow_size = CONFIG.PLAYER_SIZE + 4
    api.fill_rect(player_screen_x - glow_size, player_screen_y - glow_size, glow_size * 2, glow_size * 2)
    
    -- Player body
    api.set_color(my_color[1], my_color[2], my_color[3])
    api.fill_rect(player_screen_x - CONFIG.PLAYER_SIZE, player_screen_y - CONFIG.PLAYER_SIZE, 
                  CONFIG.PLAYER_SIZE * 2, CONFIG.PLAYER_SIZE * 2)
    
    -- Player inner highlight
    api.set_color(
        math.min(255, math.floor(my_color[1] * 1.3)),
        math.min(255, math.floor(my_color[2] * 1.3)),
        math.min(255, math.floor(my_color[3] * 1.3))
    )
    local inner = CONFIG.PLAYER_SIZE - 3
    api.fill_rect(player_screen_x - inner, player_screen_y - inner, inner * 2, inner * 2)
    
    -- Draw own chat messages above player
    local msg_y = player_screen_y - 32
    for i = #player.chat_messages, math.max(1, #player.chat_messages - 2), -1 do
        local msg = player.chat_messages[i]
        if msg then
            api.set_color(255, 255, 200)
            api.draw_text(msg.text, player_screen_x - 30, msg_y)
            msg_y = msg_y - 12
        end
    end
    
    -- Draw HUD background (moved right and down to avoid edge cutoff)
    local hud_x = 10
    local hud_y = 10
    local hud_w = 320
    local hud_h = 90
    
    api.set_color(20, 25, 35, 220)
    api.fill_rect(hud_x, hud_y, hud_w, hud_h)
    
    -- HUD border (all 4 sides)
    api.set_color(60, 70, 90)
    api.draw_line(hud_x, hud_y, hud_x + hud_w, hud_y, 2)                      -- Top
    api.draw_line(hud_x, hud_y, hud_x, hud_y + hud_h, 2)                      -- Left
    api.draw_line(hud_x, hud_y + hud_h, hud_x + hud_w, hud_y + hud_h, 2)      -- Bottom
    api.draw_line(hud_x + hud_w, hud_y, hud_x + hud_w, hud_y + hud_h, 2)      -- Right
    
    -- Title
    api.set_color(100, 200, 255)
    api.draw_text("PROXIMITY EXPLORER", hud_x + 10, hud_y + 15)
    
    -- Coordinates
    api.set_color(200, 200, 200)
    api.draw_text("X: " .. math.floor(px) .. "  Y: " .. math.floor(py), hud_x + 10, hud_y + 35)
    
    -- Count nearby players
    local nearby_count = 0
    for _, _ in ipairs(nearby) do nearby_count = nearby_count + 1 end
    nearby_count = nearby_count - 1  -- Exclude self
    if nearby_count < 0 then nearby_count = 0 end
    
    if nearby_count > 0 then
        api.set_color(100, 255, 100)
    else
        api.set_color(150, 150, 150)
    end
    api.draw_text("Nearby: " .. nearby_count .. " player(s)", hud_x + 10, hud_y + 55)
    
    -- Controls hint
    api.set_color(120, 120, 140)
    api.draw_text("WASD/Arrows: Move  |  Enter: Chat", hud_x + 10, hud_y + 75)
    
    -- Draw chat input if active
    if player.chat_input_active then
        api.set_color(25, 30, 40, 240)
        api.fill_rect(0, 555, 800, 45)
        api.set_color(80, 100, 140)
        api.draw_line(0, 555, 800, 555, 2)
        api.set_color(255, 255, 255)
        api.draw_text("Chat: " .. (player.chat_buffer or "") .. "_", 10, 572)
        api.set_color(150, 150, 170)
        api.draw_text("[Enter] Send  [Esc] Cancel", 550, 572)
    end
    
    -- Seed info badge (positioned below main HUD)
    local seed_x = 10
    local seed_y = 105
    local seed_w = 150
    local seed_h = 24
    
    api.set_color(40, 45, 60, 200)
    api.fill_rect(seed_x, seed_y, seed_w, seed_h)
    
    -- Seed border (all 4 sides)
    api.set_color(60, 70, 90)
    api.draw_line(seed_x, seed_y, seed_x + seed_w, seed_y, 2)                      -- Top
    api.draw_line(seed_x, seed_y, seed_x, seed_y + seed_h, 2)                      -- Left
    api.draw_line(seed_x, seed_y + seed_h, seed_x + seed_w, seed_y + seed_h, 2)    -- Bottom
    api.draw_line(seed_x + seed_w, seed_y, seed_x + seed_w, seed_y + seed_h, 2)    -- Right
    
    api.set_color(180, 180, 220)
    api.draw_text("Seed: " .. CONFIG.SEED_OFFSET, seed_x + 10, seed_y + 14)
end

-- ============================================================================
-- NETWORK EVENTS
-- ============================================================================
function on_connect(session_id)
    print("Player connected: " .. session_id)
    
    -- Use session_id to seed spawn location for some variety
    local seed_offset = 0
    for i = 1, #session_id do
        seed_offset = seed_offset + string.byte(session_id, i)
    end
    rng_state = seed_offset
    
    -- Spawn near the reference point (100, 753) with some randomness
    local spawn_x = 100 + simple_random(0, 300)
    local spawn_y = 753 + simple_random(0, 300)
    
    -- Make sure spawn is passable
    local attempts = 0
    while not is_tile_passable(spawn_x, spawn_y) and attempts < 100 do
        spawn_x = spawn_x + simple_random(-32, 32)
        spawn_y = spawn_y + simple_random(-32, 32)
        -- Keep within world bounds
        spawn_x = math.max(50, math.min(CONFIG.WORLD_WIDTH - 50, spawn_x))
        spawn_y = math.max(50, math.min(CONFIG.WORLD_HEIGHT - 50, spawn_y))
        attempts = attempts + 1
    end
    
    -- Create player entity in spatial DB
    local entity_id = db:add_circle(spawn_x, spawn_y, CONFIG.PLAYER_SIZE, "player")
    
    players[session_id] = {
        x = spawn_x,
        y = spawn_y,
        entity_id = entity_id,
        inputs = {},
        chat_messages = {},
        chat_buffer = "",
        chat_input_active = false,
        name = nil,  -- Set when player enters username
        name_buffer = "",  -- Buffer for typing username
        entering_name = true,  -- Start in name entry mode
        name_error = nil,  -- Error message if name is taken
    }
    
    print("Player " .. session_id .. " connected, awaiting username...")
end

function on_disconnect(session_id)
    print("Player disconnected: " .. session_id)
    
    local player = players[session_id]
    if player then
        -- Free up the username
        if player.name then
            usernames[string.lower(player.name)] = nil
        end
        db:remove(player.entity_id)
        players[session_id] = nil
    end
end

function on_input(session_id, key_code, is_down)
    local player = players[session_id]
    if not player then return end
    
    -- Handle username entry mode
    if player.entering_name then
        if is_down then
            if key_code == 13 then  -- Enter - submit username
                local name = player.name_buffer
                if #name >= 2 and #name <= 16 then
                    local name_lower = string.lower(name)
                    if usernames[name_lower] then
                        player.name_error = "Username already taken!"
                    else
                        -- Username is valid and unique
                        usernames[name_lower] = true
                        player.name = name
                        player.entering_name = false
                        player.name_error = nil
                        print("Player " .. session_id .. " joined as: " .. name)
                        print("Player " .. name .. " spawned at (" .. math.floor(player.x) .. ", " .. math.floor(player.y) .. ")")
                    end
                else
                    player.name_error = "Name must be 2-16 characters"
                end
            elseif key_code == 8 then  -- Backspace
                if #player.name_buffer > 0 then
                    player.name_buffer = string.sub(player.name_buffer, 1, -2)
                    player.name_error = nil
                end
            elseif key_code >= 32 and key_code <= 126 then
                -- Printable ASCII
                if #player.name_buffer < 16 then
                    local char = string.char(key_code)
                    if key_code >= 65 and key_code <= 90 then
                        char = string.lower(char)
                    end
                    -- Only allow alphanumeric and underscore
                    if char:match("[%w_]") then
                        player.name_buffer = player.name_buffer .. char
                        player.name_error = nil
                    end
                end
            end
        end
        return  -- Don't process other input while entering name
    end
    
    -- Handle Enter key for chat
    if key_code == 13 then  -- Enter
        if is_down then
            if player.chat_input_active then
                -- Send chat message
                if player.chat_buffer and #player.chat_buffer > 0 then
                    local msg = {
                        text = player.chat_buffer,
                        time = game_time,
                    }
                    table.insert(player.chat_messages, msg)
                    
                    -- Keep only last N messages
                    while #player.chat_messages > CONFIG.MAX_CHAT_HISTORY do
                        table.remove(player.chat_messages, 1)
                    end
                    
                    print("[CHAT] " .. player.name .. ": " .. player.chat_buffer)
                end
                player.chat_buffer = ""
                player.chat_input_active = false
            else
                player.chat_input_active = true
            end
        end
        return
    end
    
    -- Handle Escape to cancel chat
    if key_code == 27 and is_down then  -- Escape
        player.chat_input_active = false
        player.chat_buffer = ""
        return
    end
    
    -- Handle chat input (only when chat is active)
    if player.chat_input_active then
        if is_down then
            if key_code == 8 then  -- Backspace
                if #player.chat_buffer > 0 then
                    player.chat_buffer = string.sub(player.chat_buffer, 1, -2)
                end
            elseif key_code >= 32 and key_code <= 126 then
                -- Printable ASCII characters
                -- Handle shift for uppercase (basic support)
                local char = string.char(key_code)
                -- Convert to lowercase by default (key codes come as uppercase)
                if key_code >= 65 and key_code <= 90 then
                    char = string.lower(char)
                end
                player.chat_buffer = player.chat_buffer .. char
            end
        end
        return  -- Don't process movement when chatting
    end
    
    -- Store input state for movement
    player.inputs[key_code] = is_down
end

