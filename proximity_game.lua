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
    VISIBILITY_RANGE = 100,     -- Max pixels players can see each other
    CHAT_RANGE = 100,           -- Max pixels for chat visibility
    PLAYER_SPEED = 150,         -- Pixels per second
    PLAYER_SIZE = 8,            -- Player circle radius
    WORLD_WIDTH = 2000,         -- Total world width
    WORLD_HEIGHT = 2000,        -- Total world height
    TILE_SIZE = 32,             -- Size of each map tile
    SEED_OFFSET = 12345,        -- Base seed for generation
    CHAT_DURATION = 5,          -- Seconds chat messages stay visible
    MAX_CHAT_HISTORY = 10,      -- Max chat messages per player
}

-- Game state
local db = nil
local players = {}
local chat_messages = {}
local world_tiles = {}  -- Cache for generated tiles

-- ============================================================================
-- SEEDED RANDOM NUMBER GENERATOR (Deterministic based on position)
-- ============================================================================
local function hash(x, y, seed)
    -- Simple hash function for deterministic terrain
    local n = x + y * 57 + seed * 131
    n = bit32.bxor(bit32.lshift(n, 13), n)
    n = n * (n * n * 15731 + 789221) + 1376312589
    return bit32.band(n, 0x7fffffff) / 0x7fffffff
end

local function get_tile_type(world_x, world_y)
    -- Calculate tile coordinates
    local tile_x = math.floor(world_x / CONFIG.TILE_SIZE)
    local tile_y = math.floor(world_y / CONFIG.TILE_SIZE)
    local key = tile_x .. "," .. tile_y
    
    -- Check cache first
    if world_tiles[key] ~= nil then
        return world_tiles[key]
    end
    
    -- Generate tile based on seed (x:100, y:753 always same due to deterministic hash)
    local value = hash(tile_x, tile_y, CONFIG.SEED_OFFSET)
    
    local tile_type
    if value < 0.15 then
        tile_type = "water"     -- Impassable water
    elseif value < 0.30 then
        tile_type = "rock"      -- Impassable rock
    elseif value < 0.45 then
        tile_type = "tree"      -- Blocking trees
    elseif value < 0.70 then
        tile_type = "grass"     -- Normal grass
    else
        tile_type = "sand"      -- Sandy ground
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
-- TILE COLORS
-- ============================================================================
local TILE_COLORS = {
    water = {30, 90, 150},
    rock = {80, 70, 70},
    tree = {20, 80, 30},
    grass = {50, 120, 50},
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
-- INITIALIZATION
-- ============================================================================
function init()
    db = api.new_spatial_db(CONFIG.VISIBILITY_RANGE)
    print("Proximity Explorer initialized!")
    print("World size: " .. CONFIG.WORLD_WIDTH .. "x" .. CONFIG.WORLD_HEIGHT)
    print("Visibility range: " .. CONFIG.VISIBILITY_RANGE .. "px")
end

-- ============================================================================
-- UPDATE LOOP
-- ============================================================================
function update(dt)
    local current_time = os.clock()
    
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
        
        -- Calculate new position
        local speed = CONFIG.PLAYER_SPEED * dt
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
            if current_time - msg.time < CONFIG.CHAT_DURATION then
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
    
    local px, py = player.x, player.y
    local cam_x = px - 400  -- Center camera on player (800/2)
    local cam_y = py - 300  -- Center camera on player (600/2)
    
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
    api.set_color(40, 45, 50, 100)
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
        local x1 = 400 + math.cos(angle1) * CONFIG.VISIBILITY_RANGE
        local y1 = 300 + math.sin(angle1) * CONFIG.VISIBILITY_RANGE
        local x2 = 400 + math.cos(angle2) * CONFIG.VISIBILITY_RANGE
        local y2 = 300 + math.sin(angle2) * CONFIG.VISIBILITY_RANGE
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
                    
                    -- Draw player body
                    api.set_color(color[1], color[2], color[3], math.floor(alpha * 255))
                    -- Draw as filled circle (approximated with multiple rectangles)
                    for r = CONFIG.PLAYER_SIZE, 1, -1 do
                        local size = r * 2
                        api.fill_rect(screen_x - r, screen_y - r, size, size)
                    end
                    
                    -- Draw player name
                    api.set_color(255, 255, 255, math.floor(alpha * 255))
                    local name = other_player.name or ("Player " .. string.sub(other_id, 1, 4))
                    api.draw_text(name, screen_x - 20, screen_y - 20)
                    
                    -- Draw their recent chat messages (if in chat range)
                    if dist <= CONFIG.CHAT_RANGE then
                        local msg_y = screen_y - 35
                        for i = #other_player.chat_messages, math.max(1, #other_player.chat_messages - 2), -1 do
                            local msg = other_player.chat_messages[i]
                            if msg then
                                api.set_color(255, 255, 200, math.floor(alpha * 200))
                                api.draw_text(msg.text, screen_x - 30, msg_y)
                                msg_y = msg_y - 12
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Draw current player (always visible, centered)
    local my_color = get_player_color(session_id)
    api.set_color(my_color[1], my_color[2], my_color[3])
    for r = CONFIG.PLAYER_SIZE, 1, -1 do
        api.fill_rect(400 - r, 300 - r, r * 2, r * 2)
    end
    
    -- Draw own chat messages above player
    local msg_y = 270
    for i = #player.chat_messages, math.max(1, #player.chat_messages - 2), -1 do
        local msg = player.chat_messages[i]
        if msg then
            api.set_color(255, 255, 200, 255)
            api.draw_text(msg.text, 370, msg_y)
            msg_y = msg_y - 12
        end
    end
    
    -- Draw HUD
    api.set_color(20, 25, 35, 200)
    api.fill_rect(0, 0, 200, 100)
    
    api.set_color(255, 255, 255)
    api.draw_text("PROXIMITY EXPLORER", 10, 10)
    api.draw_text("X: " .. math.floor(px) .. " Y: " .. math.floor(py), 10, 30)
    
    -- Count nearby players
    local nearby_count = 0
    for _, _ in ipairs(nearby) do nearby_count = nearby_count + 1 end
    nearby_count = nearby_count - 1  -- Exclude self
    if nearby_count < 0 then nearby_count = 0 end
    
    api.set_color(100, 255, 100)
    api.draw_text("Nearby: " .. nearby_count .. " players", 10, 50)
    
    -- Chat input hint
    api.set_color(150, 150, 150)
    api.draw_text("Press ENTER to chat", 10, 70)
    
    -- Draw chat input if active
    if player.chat_input_active then
        api.set_color(30, 35, 45, 230)
        api.fill_rect(0, 560, 800, 40)
        api.set_color(255, 255, 255)
        api.draw_text("Chat: " .. (player.chat_buffer or "") .. "_", 10, 575)
    end
    
    -- Coordinates badge for seed verification
    api.set_color(60, 65, 80, 200)
    api.fill_rect(620, 0, 180, 30)
    api.set_color(200, 200, 255)
    api.draw_text("Seed: fixed @100,753", 630, 8)
end

-- ============================================================================
-- NETWORK EVENTS
-- ============================================================================
function on_connect(session_id)
    print("Player connected: " .. session_id)
    
    -- Spawn at the special seed location (100, 753) for testing
    -- Or random spawn
    local spawn_x = 100 + math.random(0, 200)
    local spawn_y = 753 + math.random(0, 200)
    
    -- Make sure spawn is passable
    local attempts = 0
    while not is_tile_passable(spawn_x, spawn_y) and attempts < 50 do
        spawn_x = spawn_x + math.random(-50, 50)
        spawn_y = spawn_y + math.random(-50, 50)
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
        name = "Player " .. string.sub(session_id, 1, 4),
    }
    
    print("Player " .. session_id .. " spawned at (" .. spawn_x .. ", " .. spawn_y .. ")")
end

function on_disconnect(session_id)
    print("Player disconnected: " .. session_id)
    
    local player = players[session_id]
    if player then
        db:remove(player.entity_id)
        players[session_id] = nil
    end
end

function on_input(session_id, key_code, is_down)
    local player = players[session_id]
    if not player then return end
    
    -- Handle Enter key for chat
    if key_code == 13 then  -- Enter
        if is_down then
            if player.chat_input_active then
                -- Send chat message
                if player.chat_buffer and #player.chat_buffer > 0 then
                    local msg = {
                        text = player.chat_buffer,
                        time = os.clock(),
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
                -- Printable ASCII
                player.chat_buffer = player.chat_buffer .. string.char(key_code)
            end
        end
        return  -- Don't process movement when chatting
    end
    
    -- Store input state for movement
    player.inputs[key_code] = is_down
end

-- ============================================================================
-- TEXT INPUT (if supported by engine)
-- ============================================================================
function on_text(session_id, text)
    local player = players[session_id]
    if player and player.chat_input_active then
        player.chat_buffer = player.chat_buffer .. text
    end
end
