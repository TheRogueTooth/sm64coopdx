
if incompatibleClient then return 0 end

-- Couch co-op character picker
-- Character Select's own menu has one selection and fills the whole screen. With more
-- than one local player it's turned off and each player gets this picker in their own
-- half of the screen instead. Picks live in gCSCouchSeats (a-utils.lua)

-- Listed first, in this order. Everyone else follows in the order they were loaded
local PICKER_ORDER = { "Mario", "Luigi", "Peach", "Rosalina", "Mallow", "Geno", "Toad", "Toadette", "Daisy", "Yoshi", "Birdo", "Pauline", "Foreman Spike", "Wario", "Waluigi", "Donkey Kong", "Luma", "Honey Queen", "Bowser", "Bowser Jr", "Larry Koopa", "Morton Koopa Jr", "Wendy O' Koopa", "Iggy Koopa", "Roy Koopa", "Lemmy Koopa", "Ludwig von Koopa", "Goomba", "Penguin", "Conkdor", "Jinjo" }
-- Not shown in the picker. Remove a name to make them selectable
local PICKER_HIDDEN = { ["Sonic"] = true, ["WaPeach"] = true }

local PICKER_ROWS = 5
local HINT_FRAMES = 300
local STICK_THRESHOLD = 40
local STICK_REPEAT_FRAMES = 8

local sRoster = {}
local sRosterSize = 0
local sSeatsLoaded = false

local sPickers = {}
for i = 0, 3 do
    sPickers[i] = { open = false, cursor = 1, stall = 0, hint = HINT_FRAMES, undoChar = 1, undoAlt = 1 }
end

local function clean_name(name)
    return string_underscore_to_space(tostring(name))
end

local function build_roster()
    sRoster = {}
    for c = 1, #characterTable do
        local character = characterTable[c]
        if not character.locked then
            if c == 1 then
                -- Default's "costumes" are really the five base characters
                for alt = 1, #character do
                    table.insert(sRoster, { char = c, fixedAlt = alt, name = clean_name(character[alt].name) })
                end
            else
                local name = clean_name(character[1].name)
                if not PICKER_HIDDEN[name] then
                    table.insert(sRoster, { char = c, name = name })
                end
            end
        end
    end

    local rank = {}
    for i, name in ipairs(PICKER_ORDER) do rank[name] = i end
    for i, entry in ipairs(sRoster) do entry.loadOrder = i end
    table.sort(sRoster, function(a, b)
        local rankA, rankB = rank[a.name] or math.huge, rank[b.name] or math.huge
        if rankA ~= rankB then return rankA < rankB end
        return a.loadOrder < b.loadOrder
    end)
    sRosterSize = #characterTable
end

local function seat_storage_key(index, field)
    return "Couch" .. index .. field
end

local function load_seats()
    for i = 0, 3 do
        local seat = gCSCouchSeats[i]
        local savedName = mod_storage_load(seat_storage_key(i, "Char"))
        local savedAlt = tonumber(mod_storage_load(seat_storage_key(i, "Alt")))
        if savedName ~= nil and savedName ~= "" then
            for c = 1, #characterTable do
                if characterTable[c].saveName == savedName and not characterTable[c].locked then
                    seat.char = c
                    seat.alt = (savedAlt ~= nil and savedAlt >= 1 and savedAlt <= #characterTable[c]) and savedAlt or 1
                    break
                end
            end
        end
    end
end

local function save_seat(index)
    local seat = gCSCouchSeats[index]
    mod_storage_save(seat_storage_key(index, "Char"), characterTable[seat.char].saveName)
    mod_storage_save(seat_storage_key(index, "Alt"), tostring(seat.alt))
end

local function find_cursor(seat)
    for i, entry in ipairs(sRoster) do
        if entry.char == seat.char and (entry.fixedAlt == nil or entry.fixedAlt == seat.alt) then
            return i
        end
    end
    return 1
end

local function apply_cursor(picker, seat)
    local entry = sRoster[picker.cursor]
    seat.char = entry.char
    seat.alt = entry.fixedAlt or 1
end

-- Character test: L + D-Pad Up steps player 1 through every character and costume,
-- jumping and punching as each one, and writes each step to couch-log.txt. Anything that
-- goes wrong shows up in the log straight after the character that caused it
local TEST_FRAMES_PER_COSTUME = 120
local TEST_JUMP_FRAME = 40
local TEST_PUNCH_FRAME = 90
local sTest = nil

local function test_apply(step)
    if cs_couch_active() then
        -- Both players at once, which also covers two of the same character
        gCSCouchSeats[0].char, gCSCouchSeats[0].alt = step.char, step.alt
        gCSCouchSeats[1].char, gCSCouchSeats[1].alt = step.char, step.alt
    else
        currChar = step.char
        characterTable[step.char].currAlt = step.alt
    end
end

local function test_start()
    local steps = {}
    for c = 1, #characterTable do
        for alt = 1, #characterTable[c] do
            table.insert(steps, { char = c, alt = alt })
        end
    end
    sTest = {
        steps = steps,
        index = 0,
        timer = 0,
        undo = {
            char = currChar,
            alt = characterTable[currChar].currAlt,
            seats = {
                [0] = { char = gCSCouchSeats[0].char, alt = gCSCouchSeats[0].alt },
                [1] = { char = gCSCouchSeats[1].char, alt = gCSCouchSeats[1].alt },
            },
        },
    }
    log_to_console("[test] start: " .. #steps .. " costumes", 0)
end
gCSCouchTestStart = test_start

local function test_finish()
    local undo = sTest.undo
    currChar = undo.char
    characterTable[undo.char].currAlt = undo.alt
    for i = 0, 1 do
        gCSCouchSeats[i].char, gCSCouchSeats[i].alt = undo.seats[i].char, undo.seats[i].alt
    end
    log_to_console("[test] finished, no crash", 0)
    djui_popup_create("Character test finished", 3)
    sTest = nil
end

local function test_update(m)
    if sTest.timer == 0 then
        sTest.index = sTest.index + 1
        local step = sTest.steps[sTest.index]
        if step == nil then
            test_finish()
            return
        end
        test_apply(step)
        local character = characterTable[step.char]
        log_to_console("[test] " .. sTest.index .. "/" .. #sTest.steps .. " " .. clean_name(character[1].name) .. " / " .. clean_name(character[step.alt].name), 0)
        play_character_sound(m, CHAR_SOUND_HERE_WE_GO)
    end

    sTest.timer = sTest.timer + 1
    if sTest.timer == TEST_JUMP_FRAME and (m.action & ACT_FLAG_AIR) == 0 then
        set_mario_action(m, ACT_JUMP, 0)
    elseif sTest.timer == TEST_PUNCH_FRAME and (m.action & ACT_FLAG_AIR) == 0 then
        set_mario_action(m, ACT_PUNCHING, 0)
    elseif sTest.timer >= TEST_FRAMES_PER_COSTUME then
        sTest.timer = 0
    end
end

local function on_before_mario_update(m)
    if cs_context_index() == 0 then
        if sTest then
            test_update(m)
            return
        elseif (m.controller.buttonDown & L_TRIG) ~= 0 and (m.controller.buttonPressed & U_JPAD) ~= 0 and not is_game_paused() and cs_menu_is_allowed(m) then
            test_start()
            return
        end
    end
    if not cs_couch_active() then return end
    if sRosterSize ~= #characterTable then build_roster() end
    if not sSeatsLoaded then
        load_seats()
        sSeatsLoaded = true
    end

    local index = cs_context_index()
    local picker = sPickers[index]
    local seat = gCSCouchSeats[index]
    local controller = m.controller
    local cameraToObject = m.marioObj.header.gfx.cameraToObject

    if picker.stall > 0 then picker.stall = picker.stall - 1 end
    if picker.hint > 0 then picker.hint = picker.hint - 1 end

    if not picker.open then
        if (controller.buttonPressed & D_JPAD) ~= 0 and not is_game_paused() and cs_menu_is_allowed(m) then
            picker.open = true
            picker.hint = 0
            picker.cursor = find_cursor(seat)
            picker.undoChar, picker.undoAlt = seat.char, seat.alt
            play_sound(SOUND_MENU_CHANGE_SELECT, cameraToObject)
        else
            return
        end
    elseif not cs_menu_is_allowed(m) then
        picker.open = false
        return
    else
        local pressed = controller.buttonPressed
        local moveY, moveX = 0, 0
        if (pressed & U_JPAD) ~= 0 then moveY = -1 end
        if (pressed & D_JPAD) ~= 0 then moveY = 1 end
        if (pressed & L_JPAD) ~= 0 then moveX = -1 end
        if (pressed & R_JPAD) ~= 0 then moveX = 1 end
        if picker.stall == 0 and moveY == 0 and moveX == 0 then
            if controller.rawStickY > STICK_THRESHOLD then moveY = -1 end
            if controller.rawStickY < -STICK_THRESHOLD then moveY = 1 end
            if controller.rawStickX < -STICK_THRESHOLD then moveX = -1 end
            if controller.rawStickX > STICK_THRESHOLD then moveX = 1 end
            if moveY ~= 0 or moveX ~= 0 then picker.stall = STICK_REPEAT_FRAMES end
        end

        if moveY ~= 0 then
            picker.cursor = ((picker.cursor - 1 + moveY) % #sRoster) + 1
            apply_cursor(picker, seat)
            play_sound(SOUND_MENU_MESSAGE_NEXT_PAGE, cameraToObject)
        elseif moveX ~= 0 and sRoster[picker.cursor].fixedAlt == nil then
            local costumes = #characterTable[seat.char]
            if costumes > 1 then
                seat.alt = ((seat.alt - 1 + moveX) % costumes) + 1
                play_sound(SOUND_MENU_CLICK_CHANGE_VIEW, cameraToObject)
            end
        end

        if (pressed & A_BUTTON) ~= 0 then
            picker.open = false
            save_seat(index)
            play_sound(SOUND_MENU_CLICK_FILE_SELECT, cameraToObject)
        elseif (pressed & B_BUTTON) ~= 0 then
            picker.open = false
            seat.char, seat.alt = picker.undoChar, picker.undoAlt
            play_sound(SOUND_MENU_CAMERA_BUZZ, cameraToObject)
        end
    end

    -- The player stands still while they choose
    controller.buttonPressed = 0
    controller.buttonDown = 0
    controller.buttonReleased = 0
    controller.rawStickX = 0
    controller.rawStickY = 0
    controller.stickX = 0
    controller.stickY = 0
    controller.stickMag = 0
end

local function print_shadowed(text, x, y, scale, r, g, b)
    djui_hud_set_color(0, 0, 0, 200)
    djui_hud_print_text(text, x + 0.5, y + 0.5, scale)
    djui_hud_set_color(r, g, b, 255)
    djui_hud_print_text(text, x, y, scale)
end

-- Runs once per local player, already placed inside that player's half of the screen
local function on_hud_render_behind()
    if not cs_couch_active() or hud_is_hidden() then return end
    local index = cs_context_index()
    local picker = sPickers[index]

    djui_hud_set_resolution(RESOLUTION_N64)
    djui_hud_set_font(FONT_NORMAL)

    if picker.hint > 0 and not picker.open then
        print_shadowed("D-PAD DOWN: CHANGE CHARACTER", 8, djui_hud_get_screen_height() - 16, 0.25, 255, 255, 255)
        return
    end
    if not picker.open or #sRoster == 0 then return end

    local seat = gCSCouchSeats[index]
    local character = characterTable[seat.char][seat.alt]
    local screenHeight = djui_hud_get_screen_height()
    local panelX, panelY = 6, 6
    local panelWidth, panelHeight = 150, screenHeight - 12
    local textX = panelX + 6

    djui_hud_set_color(0, 0, 0, 190)
    djui_hud_render_rect(panelX, panelY, panelWidth, panelHeight)

    print_shadowed("PLAYER " .. (index + 1), textX, panelY + 3, 0.3, 255, 255, 80)

    local rows = math.min(PICKER_ROWS, #sRoster)
    local first = math.max(1, math.min(picker.cursor - math.floor(rows / 2), #sRoster - rows + 1))
    local y = panelY + 16
    for i = first, first + rows - 1 do
        local entry = sRoster[i]
        if i == picker.cursor then
            local color = character.color or { r = 255, g = 255, b = 255 }
            print_shadowed("> " .. entry.name, textX, y, 0.3, color.r, color.g, color.b)
        else
            print_shadowed("  " .. entry.name, textX, y, 0.3, 190, 190, 190)
        end
        y = y + 11
    end

    local costumes = #characterTable[seat.char]
    if sRoster[picker.cursor].fixedAlt == nil and costumes > 1 then
        print_shadowed("< " .. clean_name(character.name) .. " >", textX, y + 1, 0.25, 160, 220, 255)
    end
    print_shadowed("A:OK  B:BACK", textX, panelY + panelHeight - 10, 0.22, 255, 255, 255)
end

hook_event(HOOK_BEFORE_MARIO_UPDATE, on_before_mario_update)
hook_event(HOOK_ON_HUD_RENDER_BEHIND, on_hud_render_behind)
