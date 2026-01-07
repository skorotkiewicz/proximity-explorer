-- ============================================================================
-- NPC ASSISTANT MODULE
-- An AI-powered NPC that walks around and helps players
-- ============================================================================

local NPC = {}

-- NPC Configuration
NPC.CONFIG = {
    DETECTION_RANGE = 80,      -- Range to detect players
    WALK_SPEED = 50,           -- Slower than players
    IDLE_TIME = 2.0,           -- Seconds to wait before moving
    MOVE_TIME = 3.0,           -- Seconds to move in one direction
    NAME = "Guide",            -- NPC name
    COLOR = {255, 200, 100},   -- Golden/orange color
    SIZE = 10,                 -- Slightly larger than players
    LLM_ENDPOINT = "http://ml:8888/v1/chat/completions",
    LLM_MODEL = "gpt-3.5-turbo",
}

-- NPC State
NPC.state = {
    x = 300,
    y = 800,
    entity_id = nil,
    mode = "idle",  -- idle, walking, talking
    target_player = nil,
    direction = {x = 0, y = 0},
    timer = 0,
    conversation = {},  -- Chat history with current player
    pending_response = nil,  -- Response being typed out
    response_text = "",
    response_timer = 0,
    chat_messages = {},  -- Visible chat bubbles
}

-- Initialize NPC
function NPC.init(db, spawn_x, spawn_y)
    NPC.db = db
    NPC.state.x = spawn_x or 300
    NPC.state.y = spawn_y or 800
    NPC.state.entity_id = db:add_circle(NPC.state.x, NPC.state.y, NPC.CONFIG.SIZE, "npc")
    NPC.state.timer = NPC.CONFIG.IDLE_TIME
    print("[NPC] Guide spawned at (" .. NPC.state.x .. ", " .. NPC.state.y .. ")")
end

-- Check if a position is passable (basic check)
local function is_passable(x, y, get_tile_func)
    if get_tile_func then
        local tile = get_tile_func(x, y)
        return tile ~= "water" and tile ~= "rock"
    end
    return true
end

-- Pick a random direction
local function pick_random_direction()
    local angle = math.random() * math.pi * 2
    return {
        x = math.cos(angle),
        y = math.sin(angle)
    }
end

-- Update NPC logic
function NPC.update(dt, players, game_time, get_tile_func)
    local state = NPC.state
    local config = NPC.CONFIG
    
    -- Find nearby players
    local nearby_player = nil
    local min_dist = config.DETECTION_RANGE
    
    for session_id, player in pairs(players) do
        if player.name and not player.entering_name then  -- Only interact with named players
            local dx = player.x - state.x
            local dy = player.y - state.y
            local dist = math.sqrt(dx * dx + dy * dy)
            
            if dist < min_dist then
                min_dist = dist
                nearby_player = player
                nearby_player.session_id = session_id
            end
        end
    end
    
    -- Update chat message timers
    local new_messages = {}
    for _, msg in ipairs(state.chat_messages) do
        if game_time - msg.time < 5 then  -- 5 second display
            table.insert(new_messages, msg)
        end
    end
    state.chat_messages = new_messages
    
    -- Handle response typing animation
    if state.pending_response and #state.pending_response > 0 then
        state.response_timer = state.response_timer + dt
        if state.response_timer > 0.03 then  -- Type 1 char every 30ms
            state.response_timer = 0
            state.response_text = state.response_text .. string.sub(state.pending_response, 1, 1)
            state.pending_response = string.sub(state.pending_response, 2)
            
            -- When done typing, add to chat
            if #state.pending_response == 0 then
                table.insert(state.chat_messages, {
                    text = state.response_text,
                    time = game_time,
                    from_npc = true
                })
                state.response_text = ""
            end
        end
    end
    
    -- Mode logic
    if nearby_player then
        -- Player nearby - stop and face them
        state.mode = "talking"
        state.target_player = nearby_player
    else
        -- No player nearby
        state.target_player = nil
        state.timer = state.timer - dt
        
        if state.mode == "talking" then
            -- Player left - clear conversation
            state.conversation = {}
            state.mode = "idle"
            state.timer = config.IDLE_TIME
        elseif state.mode == "idle" then
            if state.timer <= 0 then
                -- Start walking
                state.mode = "walking"
                state.direction = pick_random_direction()
                state.timer = config.MOVE_TIME
            end
        elseif state.mode == "walking" then
            if state.timer <= 0 then
                -- Stop walking
                state.mode = "idle"
                state.timer = config.IDLE_TIME
            else
                -- Move in current direction
                local new_x = state.x + state.direction.x * config.WALK_SPEED * dt
                local new_y = state.y + state.direction.y * config.WALK_SPEED * dt
                
                -- World bounds
                new_x = math.max(50, math.min(1950, new_x))
                new_y = math.max(50, math.min(1950, new_y))
                
                -- Check passability
                if is_passable(new_x, new_y, get_tile_func) then
                    state.x = new_x
                    state.y = new_y
                    NPC.db:update(state.entity_id, state.x, state.y)
                else
                    -- Hit obstacle, pick new direction
                    state.direction = pick_random_direction()
                end
            end
        end
    end
end

-- Handle player message to NPC
function NPC.receive_message(player, message, game_time)
    local state = NPC.state
    
    -- Only respond if this player is nearby
    if state.target_player and state.target_player.session_id == player.session_id then
        -- Add to conversation history
        table.insert(state.conversation, {
            role = "user",
            content = message
        })
        
        -- Try LLM first, fallback to pattern matching
        local response = NPC.call_llm_sync(state.conversation)
        
        table.insert(state.conversation, {
            role = "assistant", 
            content = response
        })
        
        -- Start typing animation
        state.pending_response = response
        state.response_text = ""
        state.response_timer = 0
        
        print("[NPC] Received: " .. message)
        print("[NPC] Response: " .. response)
    end
end

-- Generate LLM response (pattern matching fallback)
function NPC.generate_response(message)
    local msg_lower = string.lower(message)
    
    if msg_lower:find("hello") or msg_lower:find("hi") or msg_lower:find("hey") then
        return "Hello, traveler! I'm the Guide. Ask me anything about this world!"
    elseif msg_lower:find("help") then
        return "I can help! Use WASD to move, Enter to chat. Find other players nearby!"
    elseif msg_lower:find("who") and msg_lower:find("you") then
        return "I'm the Guide NPC! I wander this procedural world helping adventurers."
    elseif msg_lower:find("where") then
        return "You're in Proximity Explorer! A procedurally generated world with seed 77777."
    elseif msg_lower:find("how") and msg_lower:find("play") then
        return "Explore the world! You can only see players within 100 pixels. Chat is proximity-based too!"
    elseif msg_lower:find("water") then
        return "Water tiles are impassable. Stick to grass, sand, and forest paths!"
    elseif msg_lower:find("rock") then
        return "Rocky terrain blocks your path. Navigate around the mountains!"
    elseif msg_lower:find("sand") then
        return "Sand slows you down by 20%. It's near water bodies and beaches."
    elseif msg_lower:find("bye") or msg_lower:find("goodbye") then
        return "Safe travels, adventurer! May you find interesting companions!"
    else
        return "Interesting question! Explore the world and discover its secrets."
    end
end

-- Make synchronous HTTP request to LLM
function NPC.call_llm_sync(messages)
    -- Check if HTTP API is available
    if not api or not api.http_post then
        -- Fallback to pattern matching
        local last_msg = messages[#messages]
        if last_msg then
            return NPC.generate_response(last_msg.content)
        end
        return "I'm thinking..."
    end
    
    -- Build system prompt for context
    local system_prompt = [[You are a helpful NPC Guide in a multiplayer exploration game called Proximity Explorer. 
You wander a procedurally generated 2000x2000 world with seed 77777.
The world has water (blue, impassable), rocks (gray, impassable), sand (tan, slows movement), grass (green), and trees (dark green).
Players can only see each other within 100 pixels and can only chat with nearby players.
Controls: WASD or arrow keys to move, Enter to chat.
Keep responses SHORT (1-2 sentences max). Be friendly and helpful.]]

    -- Build messages array with system prompt
    local llm_messages = {
        { role = "system", content = system_prompt }
    }
    
    -- Add conversation history (last 6 messages max to keep context small)
    local start_idx = math.max(1, #messages - 6)
    for i = start_idx, #messages do
        table.insert(llm_messages, messages[i])
    end
    
    -- Build request body
    local request_body = {
        model = NPC.CONFIG.LLM_MODEL,
        messages = llm_messages,
        max_tokens = 100,
        temperature = 0.7
    }
    
    -- Make HTTP request
    local response_body, err = api.http_post(NPC.CONFIG.LLM_ENDPOINT, request_body)
    
    if err then
        print("[NPC] LLM Error: " .. err)
        -- Fallback to pattern matching
        local last_msg = messages[#messages]
        if last_msg then
            return NPC.generate_response(last_msg.content)
        end
        return "I'm having trouble thinking..."
    end
    
    -- Parse JSON response
    local response, parse_err = api.json_decode(response_body)
    if parse_err then
        print("[NPC] JSON Parse Error: " .. parse_err)
        local last_msg = messages[#messages]
        if last_msg then
            return NPC.generate_response(last_msg.content)
        end
        return "I got confused..."
    end
    
    -- Extract response text
    if response and response.choices and response.choices[1] and response.choices[1].message then
        local content = response.choices[1].message.content
        -- Truncate if too long
        if #content > 150 then
            content = string.sub(content, 1, 147) .. "..."
        end
        return content
    end
    
    -- Fallback
    local last_msg = messages[#messages]
    if last_msg then
        return NPC.generate_response(last_msg.content)
    end
    return "I'm not sure what to say..."
end

-- Draw NPC (called from main draw function)
function NPC.draw(cam_x, cam_y, player_x, player_y, api)
    local state = NPC.state
    local config = NPC.CONFIG
    
    -- Calculate distance to viewer
    local dx = state.x - player_x
    local dy = state.y - player_y
    local dist = math.sqrt(dx * dx + dy * dy)
    
    -- Only draw if within visibility range (same as players)
    if dist > 150 then return end  -- Slightly larger range for NPC
    
    -- Calculate screen position
    local screen_x = state.x - cam_x
    local screen_y = state.y - cam_y
    
    -- Check if on screen
    if screen_x < -20 or screen_x > 820 or screen_y < -20 or screen_y > 620 then
        return
    end
    
    -- Calculate visibility alpha
    local alpha = 255
    if dist > 100 then
        alpha = math.floor(255 * (1 - (dist - 100) / 50))
    end
    
    -- Draw NPC body (golden circle)
    api.set_color(config.COLOR[1], config.COLOR[2], config.COLOR[3], alpha)
    api.fill_rect(screen_x - config.SIZE, screen_y - config.SIZE, 
                  config.SIZE * 2, config.SIZE * 2)
    
    -- Draw NPC border
    api.set_color(255, 255, 255, alpha)
    api.draw_line(screen_x - config.SIZE, screen_y - config.SIZE, 
                  screen_x + config.SIZE, screen_y - config.SIZE, 2)
    api.draw_line(screen_x + config.SIZE, screen_y - config.SIZE,
                  screen_x + config.SIZE, screen_y + config.SIZE, 2)
    api.draw_line(screen_x + config.SIZE, screen_y + config.SIZE,
                  screen_x - config.SIZE, screen_y + config.SIZE, 2)
    api.draw_line(screen_x - config.SIZE, screen_y + config.SIZE,
                  screen_x - config.SIZE, screen_y - config.SIZE, 2)
    
    -- Draw name above NPC
    api.set_color(255, 220, 100, alpha)
    api.draw_text(config.NAME, screen_x - 15, screen_y - config.SIZE - 18)
    
    -- Draw mode indicator
    if state.mode == "talking" then
        api.set_color(100, 255, 100, alpha)
        api.draw_text("...", screen_x - 5, screen_y - config.SIZE - 8)
    end
    
    -- Draw chat messages
    local msg_y = screen_y - config.SIZE - 35
    for i = #state.chat_messages, math.max(1, #state.chat_messages - 2), -1 do
        local msg = state.chat_messages[i]
        if msg.from_npc then
            api.set_color(255, 220, 100, 220)
        else
            api.set_color(200, 200, 255, 220)
        end
        api.draw_text(msg.text, screen_x - 60, msg_y)
        msg_y = msg_y - 15
    end
    
    -- Draw currently typing response
    if #state.response_text > 0 then
        api.set_color(255, 220, 100, 200)
        api.draw_text(state.response_text .. "_", screen_x - 60, screen_y - config.SIZE - 35)
    end
end

-- Get NPC position
function NPC.get_position()
    return NPC.state.x, NPC.state.y
end

-- Check if NPC is talking to a specific player
function NPC.is_talking_to(session_id)
    return NPC.state.target_player and NPC.state.target_player.session_id == session_id
end

return NPC
