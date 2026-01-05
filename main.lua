-- Called once when the server starts
function init()
    -- Initialize physics, load assets, setup state
    db = api.new_spatial_db(250)
    phys = api.new_physics_world(db)
--    api.load_sound("jump", "assets/jump.wav")
end

-- Called every server frame (typically 30 TPS)
function update(dt)
    -- Advance physics simulation
    phys:step(dt)

    -- Handle collisions
    local events = phys:get_collision_events()
    for _, pair in ipairs(events) do
        -- Handle game logic (damage, score)
    end
end

-- Called for EACH connected client to generate their frame
function draw(session_id)
    api.clear_screen(20, 20, 30)

    -- Draw player-specific view (camera, HUD)
    local p = players[session_id]
    if p then
        api.set_color(255, 255, 255)
        api.draw_text("HP: " .. p.hp, 10, 10)
        -- Use db:query_rect to draw visible entities
    end
end

-- Network Events
function on_connect(session_id)
    print("Player joined: " .. session_id)
    -- Spawn player entity
end

function on_disconnect(session_id)
    print("Player left: " .. session_id)
    -- Despawn entity
end

function on_input(session_id, key_code, is_down)
    -- Handle input (key_code is JS key code)
    -- 37=Left, 38=Up, 39=Right, 40=Down, 32=Space, 90=Z
    if players[session_id] then
        players[session_id].inputs[key_code] = is_down
    end
end
