if incompatibleClient then return 0 end

-- localize functions to improve performance - z-palettes.lua
local network_player_set_override_palette_color,network_player_reset_override_palette = network_player_set_override_palette_color,network_player_reset_override_palette


characterColorPresets = {
    [E_MODEL_MARIO] = {
        currPalette = 0,
        [1] = {
            [PANTS]  = { r = 0x00, g = 0x00, b = 0xff },
            [SHIRT]  = { r = 0xff, g = 0x00, b = 0x00 },
            [GLOVES] = { r = 0xff, g = 0xff, b = 0xff },
            [SHOES]  = { r = 0x72, g = 0x1c, b = 0x0e },
            [HAIR]   = { r = 0x73, g = 0x06, b = 0x00 },
            [SKIN]   = { r = 0xfe, g = 0xc1, b = 0x79 },
            [CAP]    = { r = 0xff, g = 0x00, b = 0x00 },
            [EMBLEM] = { r = 0xff, g = 0x00, b = 0x00 },
        },
    },
    [E_MODEL_LUIGI] = {
        currPalette = 0,
        [1] = {
            [PANTS]  = { r = 0x00, g = 0x00, b = 0xff },
            [SHIRT]  = { r = 0x00, g = 0xff, b = 0x00 },
            [GLOVES] = { r = 0xff, g = 0xff, b = 0xff },
            [SHOES]  = { r = 0x72, g = 0x1c, b = 0x0e },
            [HAIR]   = { r = 0x73, g = 0x06, b = 0x00 },
            [SKIN]   = { r = 0xfe, g = 0xc1, b = 0x79 },
            [CAP]    = { r = 0x00, g = 0xff, b = 0x00 },
            [EMBLEM] = { r = 0x00, g = 0xff, b = 0x00 },
        },
    },
    [E_MODEL_TOAD_PLAYER] = {
        currPalette = 0,
        [1] = {
            [PANTS]  = { r = 0xff, g = 0xff, b = 0xff },
            [SHIRT]  = { r = 0x4c, g = 0x2c, b = 0xd3 },
            [GLOVES] = { r = 0xff, g = 0xff, b = 0xff },
            [SHOES]  = { r = 0x68, g = 0x40, b = 0x1b },
            [HAIR]   = { r = 0x73, g = 0x06, b = 0x00 },
            [SKIN]   = { r = 0xfe, g = 0xd5, b = 0xa1 },
            [CAP]    = { r = 0xff, g = 0x00, b = 0x00 },
            [EMBLEM] = { r = 0xff, g = 0x00, b = 0x00 },
        },
    },
    [E_MODEL_WALUIGI] = {
        currPalette = 0,
        [1] = {
            [PANTS]  = { r = 0x16, g = 0x16, b = 0x27 },
            [SHIRT]  = { r = 0x61, g = 0x26, b = 0xb0 },
            [GLOVES] = { r = 0xff, g = 0xff, b = 0xff },
            [SHOES]  = { r = 0xfe, g = 0x76, b = 0x00 },
            [HAIR]   = { r = 0x73, g = 0x53, b = 0x00 },
            [SHOES]  = { r = 0xfe, g = 0x76, b = 0x00 },
            [SKIN]   = { r = 0xfe, g = 0xc1, b = 0x79 },
            [CAP]    = { r = 0x61, g = 0x26, b = 0xb0 },
            [EMBLEM] = { r = 0xff, g = 0xde, b = 0x00 },
        },
    },
    [E_MODEL_WARIO] = {
        currPalette = 0,
        [1] = {
            [PANTS]  = { r = 0x7f, g = 0x20, b = 0x7a },
            [SHIRT]  = { r = 0xff, g = 0xbd, b = 0x00 },
            [GLOVES] = { r = 0xff, g = 0xff, b = 0xff },
            [SHOES]  = { r = 0x0e, g = 0x72, b = 0x1c },
            [HAIR]   = { r = 0x73, g = 0x53, b = 0x00 },
            [SHOES]  = { r = 0x0e, g = 0x72, b = 0x1c },
            [SKIN]   = { r = 0xfe, g = 0xc1, b = 0x79 },
            [CAP]    = { r = 0xff, g = 0xbd, b = 0x00 },
            [EMBLEM] = { r = 0x00, g = 0x00, b = 0xff },
        },
    }
}

local paletteLoop = #characterColorPresets[E_MODEL_MARIO][1]

local function network_player_set_full_override_palette(networkPlayer, colorTable)
    if colorTable == nil then return end
    for i = 0, paletteLoop do
        network_player_set_override_palette_color(networkPlayer, i, colorTable[i])
    end
end

--- @param np NetworkPlayer
local function update_preset_palette(np)
    local p = gCSPlayersRaw[np.localIndex]
    local modelId = p.modelId
    if np.connected and p.presetPalette > 0 and characterColorPresets[modelId] and not stopPalettes then
        network_player_set_full_override_palette(np, characterColorPresets[modelId][p.presetPalette])
    end
end

-- API funcs
_G.charSelect.update_preset_palette = update_preset_palette

local stallTimer = 5

local prevPresetPalette = {}
local prevModel = {}

local function mario_update(m)
    -- Palette state is per real player, m.playerIndex reads 0 for every local player
    local playerIndex = m.playerIndex == 0 and cs_context_index() or m.playerIndex
    local np = gNetworkPlayers[playerIndex]
    local p = gCSPlayersRaw[playerIndex]
    local currAlt = characterTable[currChar].currAlt

    if m.playerIndex == 0 and not p.isUpdating then
        p.isUpdating = true
        for i = 1, MAX_PLAYERS - 1 do
            prevPresetPalette[i] = gCSPlayersRaw[i].presetPalette
            prevModel[i] = gCSPlayersRaw[i].modelId
        end
    end

    if m.playerIndex == 0 then
        if not stopPalettes then
            local presets = characterColorPresets[gCSPlayers[0].modelId]
            local palette = presets ~= nil and presets.currPalette or 0
            -- Palettes get turned on from the menu that couch co-op disables, so start them on
            if palette == 0 and presets ~= nil and cs_couch_active() then palette = 1 end
            gCSPlayers[0].presetPalette = palette
        end

        if stallTimer > 0 then
            stallTimer = stallTimer - 1
        end
    end

    if np.connected then
        if p.presetPalette == nil or characterColorPresets[p.modelId] == nil then
            if p.presetPalette == nil then
                prevPresetPalette[playerIndex] = 0
            end
            p.presetPalette = 0
        end

        if (prevPresetPalette[playerIndex] ~= p.presetPalette or prevModel[playerIndex] ~= p.modelId) then
            if p.presetPalette == 0 or not characterColorPresets[p.modelId] then
                network_player_reset_override_palette(np)
            end
        end

        prevPresetPalette[playerIndex] = p.presetPalette
        prevModel[playerIndex] = p.modelId

        if p.presetPalette > 0 and characterColorPresets[p.modelId] and not stopPalettes then
            network_player_set_full_override_palette(np, characterColorPresets[p.modelId][p.presetPalette])
        end
    else
        if p.isUpdating then
            p.isUpdating = false
        end
    end
end

hook_event(HOOK_MARIO_UPDATE, mario_update)
