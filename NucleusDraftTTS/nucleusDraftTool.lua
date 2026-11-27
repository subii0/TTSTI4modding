
-- Build fair cores and slices - core is closer to rex and slices are home portions
-- deal TF Scards as reminders of speaker pick order after draft - or the tokens generated from milty

-- options:
 -- stupid home system event
 -- rich/poor/normal eco
 -- slice #
 -- faction #
 



-------------------------------------------------------------------------------

function getHelperClient(helperObjectName)
    local function getHelperObject()
        for _, object in ipairs(getAllObjects()) do
            if object.getName() == helperObjectName then return object end
        end
        error('missing object "' .. helperObjectName .. '"')
    end
    local helperObject = false
    local function getCallWrapper(functionName)
        helperObject = helperObject or getHelperObject()
        if not helperObject.getVar(functionName) then error('missing ' .. helperObjectName .. '.' .. functionName) end
        return function(parameters) return helperObject.call(functionName, parameters) end
    end
    return setmetatable({}, { __index = function(t, k) return getCallWrapper(k) end })
end

local function copyTable(t)
    if t and type(t) == 'table' then
        local copy = {}
        for k, v in pairs(t) do
            copy[k] = type(v) == 'table' and copyTable(v) or v
        end
        t = copy
    end
    return t
end

local _buttonHelper = getHelperClient('TI4_BUTTON_HELPER')
local _gameDataHelper = getHelperClient('TI4_GAME_DATA_HELPER')
local _factionHelper = getHelperClient('TI4_FACTION_HELPER')
local _setupHelper = getHelperClient('TI4_SETUP_HELPER')
local _systemHelper = getHelperClient('TI4_SYSTEM_HELPER')
local _zoneHelper = getHelperClient('TI4_ZONE_HELPER')

-------------------------------------------------------------------------------

_config = {
    DEFAULT_SLICES = 8,
    DEFAULT_FACTIONS = 8,

    MIN_SLICES = 3,
    MAX_SLICES = 10,

    MIN_FACTIONS = 3,
    MAX_FACTIONS = 12,
}

_state = false
_lastScale = false

local BUTTONS = {
    {
        id = 'ecoPreset',
        label = '<>',
        onClick = 'changeEcoPreset',
        LABEL_TEMPLATE = 'ADD TEMP LABEL',
        tooltip = 'Set slices/core to be rich, poor, or standard.'
    },
    {
        id = 'numSlices', 
        label = '<>',
        onClick = 'changeSliceCount',
        LABEL_TEMPLATE = '#Slices: !VALUE\nLeft +/Right -',
        tooltip = 'Left click to increase, right click to decrease',
    },
    {
        id = 'numFactions',
        label = '<>',
        onClick = 'changeFactionCount',
        LABEL_TEMPLATE = '#Factions: !VALUE\nLeft +/Right -',
        tooltip = 'Left click to increase, right click to decrease',
    },
    {
        id = 'setup',
        label = 'Setup',
        onClick = 'doSetup',
        tooltip = 'Place (or replace) draft slices, factions, and seat tokens',
        confirm = true,
    },
    {
        label = 'Snake draft:\nslice,\nfaction,\nor seat'
        --label = 'Reverse\nTurn\nOrder',
        --onClick = 'doReverseTurns',
        --tooltip = 'Change next player direction (forward / reverse)',
    },
    {
        id = 'finish',
        label = 'Finish',
        onClick = 'doFinish',
        tooltip = 'Move players to their drafted seats, factions, and slices (found in the drafting player\'s area)',
        confirm = true,
    }
}

local LABEL_COLORS = {
    Color.Red,
    Color.Green,
    Color.Orange,
    Color.Pink,
    Color.Yellow,
    Color.Purple,
    Color.Blue,
    Color.White,
    Color.Teal,
}

-- Expose a function for outside tools to set custom setups.
function setCustomString(customString)
    assert(type(customString) == 'string')
    if not CustomSetup.isInputVisible() then
        CustomSetup.showInput()
    end
    CustomSetup.setInputValue(customString)
end

function onLoad(saveState)
    math.randomseed(os.time())

    _state = {}
    if saveState and string.len(saveState) > 0 then
        _state = JSON.decode(saveState) or _state
    end
    _state.numSlices = _state.numSlices or _config.DEFAULT_SLICES
    _state.numFactions = _state.numFactions or _config.DEFAULT_FACTIONS
    _state.usePurples = false --Experimental setting, not saved between loads

    self.clearButtons()
    for i, button in ipairs(BUTTONS) do
        self.createButton({
            click_function = button.onClick or 'doNothing',
            function_owner = self,
            label          = button.label,
            position       = Slots.getPosition(0, i - 1, Slots.DRAFT_MAT),
            rotation       = { x = 0, y = 0, z = 0 },
            scale          = { x = 1, y = 1, z = 1 },
            width          = button.onClick and 1900 or 0,
            height         = button.onClick and 1200 or 0,
            font_size      = 240,
            font_color     = button.onClick and 'Black' or 'White',
            tooltip        = button.tooltip,
        })
        if button.confirm then
            _buttonHelper.addConfirmStep({
                guid = self.getGUID(),
                buttonIndex = i - 1,
                confirm = {
                    label = 'CLICK AGAIN\nTO CONFIRM',
                    --font_size = #,
                    -- color = string
                }
            })
        end
    end
	
    resetButtons()
	
    local snapPoints = {}
    --local lines = {}
    --local color = { r = 1, g = 1, b = 1, a = 0.1 }
    for col = 0, 0 do
        for row = 0, 5 do
            --table.insert(lines, Slots.getVectorLine(col, row, Slots.DRAFT_MAT, color))
        end
    end
    for col = 1, 3 do
        for row = 0, 5, 2 do
            table.insert(snapPoints, {
                position = Slots.getPosition(6 - col, row + 0.5, Slots.DRAFT_MAT),
                rotation = { x = 0, y = 0, z = 0 },
                rotation_snap = true,
            })
            --table.insert(lines, Slots.getVectorLine(col, row, Slots.DRAFT_MAT, color, 2))
        end
    end
    for col = 4, 6 do
        for row = 0, 5 do
            table.insert(snapPoints, {
                position = Slots.getPosition(6 - col, row, Slots.DRAFT_MAT),
                rotation = { x = 0, y = 0, z = 0 },
                rotation_snap = true,
            })
            --table.insert(lines, Slots.getVectorLine(col, row, Slots.DRAFT_MAT, color))
        end
    end
    self.setSnapPoints(snapPoints)
    self.setVectorLines({})

    local function lookAtMe(playerColor)
        Player[playerColor].lookAt({
            position = self.getPosition(),
            pitch    = 90,
            yaw      = self.getRotation().y + 180,
            distance = 30
        })
    end
    self.addContextMenuItem('Look at me', lookAtMe)
    --Temporarilly adding the purple tile option to the context menu
    self.addContextMenuItem('Toggle Red-planets', function()
        _state.usePurples = not _state.usePurples
        local var = _state.usePurples and "now" or "not"
        printToAll("The value of planets in Red-backed tiles will "..var.." be accounted for.", _state.usePurples and "Green" or "Red")
    end)

    self.addContextMenuItem('Input slices', CustomSetup.toggleInput)

    for name, value in pairs(PRESET_INPUTS) do
        local function setInput()
            _state.preset = name
            if not CustomSetup.isInputVisible() then
                CustomSetup.showInput()
            end
            CustomSetup.setInputValue(value)
            doSetup()
        end
        self.addContextMenuItem(name, setInput)
    end
end

function onSave()
    return _state and JSON.encode(_state)
end

function onPlayerTurn(player, prevPlayer)
    -- Abort if not correct turn state.
    if (not player) or (not Turns.enable) or (not Turns.order) then
        return
    end

    -- Abort if not snaking.
    if (not _state) or (not _state.snakeTurns) then
        return
    end

    -- Abort if not at the end of turn order.
    local n = #Turns.order
    local first = Turns.order[1]
    local last = Turns.order[n]
    local snakeWhen = Turns.reverse_order and first or last
    if player.color ~= snakeWhen then
        return
    end

    -- Abort if few enough player that normal turn swaps already snake.
    if n < 3 then
        return
    end

    -- At this point we are snaking and have just reached the end.  Snake!
    Turns.reverse_order = not Turns.reverse_order
    local message = {
        'Snake turn order: ',
        player.color .. ' please make two selections, ',
        'changing turn order to ',
        Turns.reverse_order and 'reverse' or 'forward'
    }
    printToAll(table.concat(message, ''), 'Yellow')
end

function _getByName(tag, name)
    for _, object in ipairs(getAllObjects()) do
        if object.tag == tag and object.getName() == name then
            return object
        end
    end
    return false
end

-------------------------------------------------------------------------------

function resetButtons()
    for i, values in ipairs(BUTTONS) do
        if values.id == 'toggleWormholesAndLegendaries' then
            local value = VolverMilty.pushWormholesLegends and 'YES' or 'NO'
            local label = string.gsub(values.LABEL_TEMPLATE, '!VALUE', value)
            self.editButton({
                index          = i - 1,
                label          = label
            })
        elseif values.id == 'numSlices' then
            local value = tostring(_state.numSlices)
            local label = string.gsub(values.LABEL_TEMPLATE, '!VALUE', value)
            self.editButton({
                index          = i - 1,
                label          = label
            })
        elseif values.id == 'numFactions' then
            local value = tostring(_state.numFactions)
            local label = string.gsub(values.LABEL_TEMPLATE, '!VALUE', value)
            self.editButton({
                index          = i - 1,
                label          = label
            })
        end
    end
end

-------------------------------------------------------------------------------

function toggleWormholesAndLegendaries()
    assert(type(VolverMilty.pushWormholesLegends) == 'boolean')
    VolverMilty.pushWormholesLegends = not VolverMilty.pushWormholesLegends
    resetButtons()
end

function changeSliceCount(clickObject, clickerColor, altClick)
    local delta = altClick and -1 or 1
    local value = _state.numSlices + delta
    if (value >= _config.MIN_SLICES) and (value <= _config.MAX_SLICES) then
        _state.numSlices = value
        resetButtons()
    else
        printToColor('Already at limit', clickerColor, 'Red')
    end
end

function changeFactionCount(clickObject, clickerColor, altClick)
    local delta = altClick and -1 or 1
    local value = _state.numFactions + delta
    if (value >= _config.MIN_FACTIONS) and (value <= _config.MAX_FACTIONS) then
        _state.numFactions = value
        resetButtons()
    else
        printToColor('Already at limit', clickerColor, 'Red')
    end
end

function doSetup()
    _state.snakeTurns = true
    startLuaCoroutine(self, 'setupCoroutine')
end

function doReverseTurns()
    Turns.reverse_order = not Turns.reverse_order
    local message = Turns.reverse_order and 'reverse' or 'forward'
    printToAll('Snake order: ' .. message, 'Yellow')
end

function doFinish()
    _state.snakeTurns = false
    startLuaCoroutine(self, 'finishCoroutine')
end

function doReset()
    startLuaCoroutine(self, 'resetCoroutine')
end

-------------------------------------------------------------------------------

function setupCoroutine()
    if _getByName('Generic', 'Game Setup Options') or (not _setupHelper.getPoK()) then
        broadcastToAll('Please do setup with PoK enabled first', 'Red')
        return 1
    end
    coroutine.yield(0)

    self.setRotation({ x = 0, y = self.getRotation().y, z = 0 })
    self.setLock(true)

    -- Put away any existing draft parts (start from scratch).
    SeatTokens.stow()
    coroutine.yield(0)

    FactionTokens.stow()
    coroutine.yield(0)

    SliceTokens.stow()
    coroutine.yield(0)

    DraftSelectionMats.stow()
    coroutine.yield(0)

    --Update which tiles to use: Only tiles in the Red/Blue bags (Homebrew tiles are assigned a tier)
    AutoTier.buildTiers(_state.usePurples)

    -- Get 3 "balanced" blue tiles and 2 red ones.
    local slices = false
    repeat
        slices = VolverMilty.makeHands(_state.numSlices)
        coroutine.yield(0)
    until slices
    _state.tileLists = assert(slices)
    VolverMilty.addRedTiles(_state.tileLists, 2)
    coroutine.yield(0)

    -- Randomize, separate any adajent anomalies.
    for i, tileList in ipairs(_state.tileLists) do
        _state.tileLists[i] = Slice.randomizeAndFixAdjacentAnomalies(tileList)
    end
    coroutine.yield(0)

    -- Randomize turns (apply at end).
    local order = {}
    for _, color in ipairs(_zoneHelper.zones()) do
        table.insert(order, color)
    end
    order = assert(VolverMilty.permute(order))

    -- Optionally override slices with manually-entered "slice string".
    local customSliceNames = {}
    local factionNames = FactionTokens.randomFactionNames(_state.numFactions)
    local mapString = false
    if CustomSetup.isInputVisible() then
        _state.tileLists = CustomSetup.readSlices() or nil
        if not _state.tileLists then
            return 1 -- assume readSlices reported the error
        end
        customSliceNames = CustomSetup.readSliceLabels() or customSliceNames
        factionNames = CustomSetup.readFactions() or factionNames
        order = CustomSetup.readDraftOrder() or order
        mapString = CustomSetup.readMapString()
        _state.clock = CustomSetup.readClock()
        CustomSetup.hideInput()
    end

    -- Build map (custom setups, not normal).
    if mapString then
        local mapTool = _getByName('Tile', 'TI4 Map Tool')
        if mapTool then
            mapTool.call('setMapString', mapString)
            mapTool.call('onButtonBuild')
        end
        coroutine.yield(0)
    end

    -- Place slices.
    for i, tileList in ipairs(_state.tileLists) do
        printToAll('Slice ' .. i .. ': ' .. table.concat(tileList, ', '), 'Yellow')
        local name = SliceTokens.getSliceName(i)
        local position = Position.draftSlice(i)
        local label = Slice.getSummary(tileList) .. '\n' .. (customSliceNames[i] or name)
        local labelColor = LABEL_COLORS[i]
        local slice = SliceTokens.spawn(tileList, name, label, labelColor, position, self.getRotation())
        local scale = slice.getScale()
        local s = 0.25
        slice.setScale({ x = scale.x * s, y = scale.y, z = scale.z * s })
        coroutine.yield(0)
        coroutine.yield(0)
    end
    coroutine.yield(0)

    -- Add seat / speaker order tokens.
    local zones = _zoneHelper.zones()
    local numSeats = #zones
    local speakerIndex = math.random(1, numSeats)
    _state.speakerColor = assert(zones[speakerIndex])
    printToAll('Speaker: ' .. _state.speakerColor, 'Yellow')
    for i, color in ipairs(_zoneHelper.zones()) do
        local speakerOrder = (((i + numSeats) - speakerIndex) % numSeats) + 1
        local label = (speakerOrder == 1) and 'SPEAKER' or tostring(speakerOrder)
        local position = Position.draftSeat(i)
        SeatTokens.moveToken(color, label, position, self.getRotation())
        coroutine.yield(0)
    end
    coroutine.yield(0)

    -- Add draft factions.
    for i, factionName in ipairs(factionNames) do
        local position = Position.draftFaction(i)
        local token = FactionTokens.placeToken(factionName, position, self.getRotation())
        coroutine.yield(0)
    end
    coroutine.yield(0)
    printToAll('Factions: ' .. table.concat(factionNames, ', '), 'Yellow')

    -- Create draft selection mats.
    for _, color in ipairs(_zoneHelper.zones()) do
        DraftSelectionMats.spawn(color)
        coroutine.yield(0)
    end

    Turns.enable = false
    Turns.type = 2
    Turns.reverse_order = false
    Turns.order = order
    Turns.turn_color = order[1]
    Turns.enable = true
    printToAll('Draft order: ' .. table.concat(order, ', '), 'Yellow')

    return 1
end

function finishCoroutine()
    if not _setupHelper.getPoK() then
        broadcastToAll('SCPT draft: please do setup with PoK enabled first', 'Red')
        return 1
    end

    -- Gather per-player choices.
    local errors = false
    local colorToChoices = {}
    for _, color in ipairs(_zoneHelper.zones()) do
        colorToChoices[color] = {
            player = false,
            sliceTiles = false,
            factionTokenName = false,
            seatColor = false
        }
    end

    for _, player in ipairs(Player.getPlayers()) do
        local color = player.color
        local choices = color and colorToChoices[color]
        if choices then
            choices.player = player
        end
    end
    coroutine.yield(0)

    for _, object in ipairs(SliceTokens.getAll(false)) do
        local zone = _zoneHelper.zoneFromPosition(object.getPosition())
        local choices = zone and colorToChoices[zone]
        if choices then
            if choices.sliceTiles then
                errors = errors or {}
                table.insert(errors, zone .. ' has multiple slice tokens')
            else
                local sliceIndex = SliceTokens.getSliceIndex(object)
                local sliceTiles = _state.tileLists[sliceIndex]
                choices.sliceTiles = assert(sliceTiles)
            end
        end
    end
    for zone, choices in pairs(colorToChoices) do
        if not choices.sliceTiles then
            errors = errors or {}
            table.insert(errors, zone .. ' does not have a slice token')
        end
    end
    coroutine.yield(0)

    local allFactionTokenNames = {}
    for _, object in ipairs(FactionTokens.getAll(true)) do
        local factionTokenName = string.match(object.getName(), '^(.*) Faction Token$')
        table.insert(allFactionTokenNames, factionTokenName)
    end
    coroutine.yield(0)

    for _, object in ipairs(FactionTokens.getAll(false)) do
        local zone = _zoneHelper.zoneFromPosition(object.getPosition())
        local choices = zone and colorToChoices[zone]
        if choices then
            if choices.factionTokenName then
                errors = errors or {}
                table.insert(errors, zone .. ' has multiple faction tokens')
            else
                local name = object.getName()
                local factionTokenName = string.match(name, '^(.*) Faction Token$')
                choices.factionTokenName = assert(factionTokenName)
            end
        end
    end
    for zone, choices in pairs(colorToChoices) do
        if not choices.factionTokenName then
            errors = errors or {}
            table.insert(errors, zone .. ' does not have a faction token')
        end
    end
    coroutine.yield(0)

    for _, object in ipairs(SeatTokens.getAll(false)) do
        local zone = _zoneHelper.zoneFromPosition(object.getPosition())
        local choices = zone and colorToChoices[zone]
        if choices then
            if choices.seatColor then
                errors = errors or {}
                table.insert(errors, zone .. ' has multiple seat/color tokens')
            else
                local color = object.getName()
                if colorToChoices[color] then
                    choices.seatColor = color
                end
            end
        end
    end
    for zone, choices in pairs(colorToChoices) do
        if not choices.seatColor then
            errors = errors or {}
            table.insert(errors, zone .. ' does not have a valid seat token')
        end
    end
    coroutine.yield(0)

    -- Abort if anything is amiss.
    if errors then
        local message = 'Error: ' .. table.concat(errors, ', ')
        broadcastToAll(message, 'Red')
        return 1
    end

    for i, color in ipairs(_zoneHelper.zones()) do
        local choices = assert(colorToChoices[color])
        local message = {
            '(' .. i .. ')',
            choices.player and choices.player.steam_name or color,
            'drafted',
            choices.factionTokenName,
            'in',
            choices.seatColor,
            'with slice {',
            table.concat(choices.sliceTiles, ', '),
            '}'
        }
        message = table.concat(message, ' ')
        printToAll(message, color)
    end
    coroutine.yield(0)

    -- Put away draft items.
    SeatTokens.stow()
    coroutine.yield(0)

    FactionTokens.stow()
    coroutine.yield(0)

    SliceTokens.stow()
    coroutine.yield(0)

    DraftSelectionMats.stow()
    coroutine.yield(0)

    -- Move cards along with players (PhilRoi feature request, not standard).
    for srcColor, choices in pairs(colorToChoices) do
        local srcPlayer = Player[srcColor]
        local srcZoneAttrs = _zoneHelper.zoneAttributes(srcColor)
        local dstColor = choices.seatColor
        local dstZoneAttrs = dstColor and _zoneHelper.zoneAttributes(dstColor)
        local srcPos = srcZoneAttrs and srcZoneAttrs.center
        local dstPos = dstZoneAttrs and dstZoneAttrs.center
        local dstRot = dstZoneAttrs and dstZoneAttrs.rotation
        if srcPlayer and srcPos and dstPos and dstRot then
            for i = 1, srcPlayer.getHandCount() do
                for j, object in ipairs(srcPlayer.getHandObjects(i)) do
                    -- Move out of hand instantly, then slide to dst.
                    object.setPosition({
                        x = srcPos.x,
                        y = srcPos.y + 3 + j * 0.2,
                        z = srcPos.z
                    })
                    object.setRotation({
                        x = 0,
                        y = dstRot.y,
                        z = 180
                    })
                    coroutine.yield(0)
                    object.setPositionSmooth({
                        x = dstPos.x,
                        y = dstPos.y + 3 + j * 0.2,
                        z = dstPos.z
                    }, false, false)
                end
            end
        end
    end

    -- Move players to their chosen seat.
    for _, choices in pairs(colorToChoices) do
        if choices.player then
            choices.player.changeColor('Grey')
            coroutine.yield(0)
            coroutine.yield(0)
        end
    end


    -- Finish move players to chosen seat.
    for _, choices in pairs(colorToChoices) do
        if choices.player then
            choices.player.changeColor(choices.seatColor)
            coroutine.yield(0)
            coroutine.yield(0)
        end
    end

    -- Move slices.
    for _, choices in pairs(colorToChoices) do
        local seatColor = assert(choices.seatColor)
        local zoneAttrs = assert(_zoneHelper.zoneAttributes(seatColor))
        local tiles = assert(choices.sliceTiles)
        local p0 = assert(zoneAttrs.homeSystemPosition)
        local applyRotation = true
        Slice.placeTiles(tiles, p0, applyRotation)
        coroutine.yield(0)
        coroutine.yield(0)
    end

    -- Setup faction on selector.
    for _, choices in pairs(colorToChoices) do
        local seatColor = assert(choices.seatColor)
        local factionTokenName = assert(choices.factionTokenName)
        _selectFaction(seatColor, factionTokenName)
        coroutine.yield(0)
    end

    -- Assign speaker.
    local speakerToken = _getByName('Generic', 'Speaker Token')
    if speakerToken then
        local zoneAttrs = _zoneHelper.zoneAttributes(_state.speakerColor)
        local pos = {
            x = zoneAttrs.center.x,
            y = zoneAttrs.center.y + 5,
            z = zoneAttrs.center.z + 6 * (zoneAttrs.center.z < 0 and 1 or -1)
        }
        local rot = {
            x = 0,
            y = zoneAttrs.rotation.y,
            z = 0
        }
        local collide = false
        local fast = false
        speakerToken.setPositionSmooth(pos, collide, fast)
        speakerToken.setRotationSmooth(rot, collide, fast)
    end
    coroutine.yield(0)

    -- Stow self.
    local toolsBag = _getByName('Bag', 'Tools and Helpers')
    if toolsBag then
        self.setLock(false)
        toolsBag.putObject(self)
    end

    -- Start timer.
    if _state.clock then
        assert(type(_state.clock) == 'number')
        local clock = false
        for _, object in ipairs(getAllObjects()) do
            if object.tag == 'Clock' then
                clock = object
            end
        end
        if clock then
            clock.setLock(true)
            clock.Clock.setValue(_state.clock)
            clock.Clock.pauseStart()
            broadcastToAll('Starting clock', 'Yellow')
        end
    end
    coroutine.yield(0)

    -- Track game type.
    _gameDataHelper.addExtraData({
        name = 'MiltyDraft',
        value = true
    })

    -- Track other data.  Do not touch 'MiltyDraft=boolean' as tools may use it.
    local extras = {}

    -- Track chosen slices in seat order.
    local pickedSlices = {}
    for i, color in ipairs(_zoneHelper.zones()) do
        local choices = assert(colorToChoices[color])
        local value = table.concat(choices.sliceTiles, ',')
        table.insert(pickedSlices, value)
    end
    extras.pickedSlices = pickedSlices

    -- Track unpicked factions.
    local pickedSet = {}
    local unpickedList = {}
    for _, choices in pairs(colorToChoices) do
        pickedSet[choices.factionTokenName] = true
    end
    for _, factionTokenName in ipairs(allFactionTokenNames) do
        if not pickedSet[factionTokenName] then
            table.insert(unpickedList, factionTokenName)
        end
    end
    extras.unpickedFactions = unpickedList

    -- Was this a right-click menu preset?
    if _state.preset then
        assert(type(_state.preset) == 'string')
        extras.preset = _state.preset
    end

    _gameDataHelper.addExtraData({
        name = 'MiltyDraftData',
        value = extras
    })

    return 1
end

function resetCoroutine()
    _state.numSlices = _config.DEFAULT_SLICES
    _state.numFactions = _config.DEFAULT_FACTIONS
    resetButtons()
    coroutine.yield(0)

    SeatTokens.stow()
    coroutine.yield(0)

    FactionTokens.stow()
    coroutine.yield(0)

    SliceTokens.stow()
    coroutine.yield(0)

    DraftSelectionMats.stow()
    coroutine.yield(0)

    return 1
end

-------------------------------------------------------------------------------

BoundingBox = {
    _bb = false
}

function BoundingBox.get(object)
    local bounds = object.getBounds()
    return {
        min = {
            x = bounds.center.x - bounds.size.x / 2,
            z = bounds.center.z - bounds.size.z / 2,
        },
        max = {
            x = bounds.center.x + bounds.size.x / 2,
            z = bounds.center.z + bounds.size.z / 2,
        },
    }
end

function BoundingBox.inside(object, bb)
    local p = object.getPosition()
    return p.x > bb.min.x and p.x < bb.max.x and p.z > bb.min.z and p.z < bb.max.z
end

function BoundingBox.insideSelf(object)
    BoundingBox._bb = BoundingBox._bb or BoundingBox.get(self)
    return BoundingBox.inside(object, BoundingBox._bb)
end

-------------------------------------------------------------------------------

Slots = {
    SIZE = {
        x = 4.04,
        z = 2.70,
        gap = 0.5,
    },
    DRAFT_MAT = {
        numCols = 7,
        numRows = 6
    },
    SELECTION_MAT = {
        numCols = 3,
        numRows = 3
    }
}

function Slots.getPosition(col, row, mat)
    assert(type(col) == 'number' and type(row) == 'number' and type(mat) == 'table')
    assert(type(mat.numCols) == 'number' and type(mat.numRows) == 'number')

    -- Not safe to read bounds while spawning.
    local bounds = {
        x = (mat.numCols * Slots.SIZE.x) + ((mat.numCols + 1) * Slots.SIZE.gap),
        y = 0.4,
        z = (mat.numRows * Slots.SIZE.z) + ((mat.numRows + 1) * Slots.SIZE.gap),
    }

    local p0 = {
        x = -(bounds.x / 2) + Slots.SIZE.gap + (Slots.SIZE.x / 2),
        y = bounds.y + 0.01,
        z = -(bounds.z / 2) + Slots.SIZE.gap + (Slots.SIZE.z / 2),
    }

    return {
        x = p0.x + col * (Slots.SIZE.x + Slots.SIZE.gap),
        y = p0.y,
        z = p0.z + row * (Slots.SIZE.z + Slots.SIZE.gap),
    }
end

function Slots.getVectorLine(col, row, mat, color, rowSpan)
    assert(type(col) == 'number' and type(row) == 'number' and type(mat) == 'table')
    assert(type(mat.numCols) == 'number' and type(mat.numRows) == 'number')

    -- Vector lines have reversed X space?
    local p1 = Slots.getPosition(col, row, mat)
    local p2 = Slots.getPosition(col, row + ((rowSpan or 1) - 1), mat)
    return {
        points = {
            { x = -p1.x, y = p1.y, z = p1.z - Slots.SIZE.z / 2 },
            { x = -p2.x, y = p2.y, z = p2.z + Slots.SIZE.z / 2 },
        },
        rotation = { x = 0, y = 0, z = 0 },
        thickness = Slots.SIZE.x,
        color = color,
        square = true,
        loop = false,
    }
end

-------------------------------------------------------------------------------

-- Mat is 7x6.  COL/ROW in 0-based values:
-- Col 0: buttons.
-- Cols 1-3: slices, offset Z by 0.5.
-- Cols 4-6:
--   Rows 1-4: factions
--   Rows 5-6: seats
Position = {
    SLICE = {
        col0 = 1,
        row0 = 0.5,
        numCols = 3
    },
    FACTION = {
        col0 = 4,
        row0 = 0,
        numCols = 3
    },
    SEAT = {
        col0 = 4,
        row0 = 4,
        numCols = 3
    },
}

function Position._pos(col, row, mat)
    local p = Slots.getPosition(col, row, mat)
    p.x = -p.x  -- x backwards from local?
    p = self.positionToWorld(p)
    p.y = p.y + 3
    return p
end

--- Where to place draftable slices during setup.
-- @param i (number) : slice index.
-- @return table : {xyz} position.
function Position.draftSlice(i)
    -- Unlike others, scale row by 2x.
    local col = Position.SLICE.col0 + ((i - 1) % Position.SLICE.numCols)
    local row = Position.SLICE.row0 + math.floor((i - 1) /  Position.SLICE.numCols) * 2
    return Position._pos(col, row, Slots.DRAFT_MAT)
end

--- Where to place draftable factions during setup.
-- @param i (number) : faction index.
-- @return table : {xyz} position.
function Position.draftFaction(i)
    local col = Position.FACTION.col0 + ((i - 1) % Position.FACTION.numCols)
    local row = Position.FACTION.row0 + math.floor((i - 1) /  Position.FACTION.numCols)
    return Position._pos(col, row, Slots.DRAFT_MAT)
end

--- Where to place draftable seats during setup.
-- @param i (number) : seat index.
-- @return table : {xyz} position.
function Position.draftSeat(i)
    local numZones = #_zoneHelper.zones()

    -- Match table positions (give up if more than fit).
    if numZones == 2 then
        i = ({ 4, 1 })[i]
    elseif numZones == 3 then
        i = ({ 4, 1, 2 })[i]
    elseif numZones == 4 then
        i = ({ 5, 4, 1, 2 })[i]
    elseif numZones == 5 then
        i = ({ 5, 4, 1, 2, 3 })[i]
    elseif numZones == 6 then
        i = ({ 6, 5, 4, 1, 2, 3 })[i]
    end

    local col = Position.SEAT.col0 + ((i - 1) % Position.SEAT.numCols)
    local row = Position.SEAT.row0 + math.floor((i - 1) /  Position.SEAT.numCols)
    return Position._pos(col, row, Slots.DRAFT_MAT)
end

-------------------------------------------------------------------------------































-- mod to do wormholes legendaries first for bonus ones








-- slice balance ands builder
-- not using a tier system bc dumb and non adaptive

--subii
-- grab list of blues
-- grab list of red
-- grab list of purple

-- random amount of good cores and good nuclei
-- tiles weighted as follows:
--   inf/res = i/r
--   tech skip + 1 | Blue +1.5
--   scar + 2
--   gravRift/nova - 2 if center otherwise -1

function runDraft()

function assignScore() -- assign a score to each tile based on the following:
    -- res/inf = i/r
    -- tech skip + .5 per planet -- round down if .5
    -- entropic scar + 2
    -- legendary planet bonus based on personal valuing :3
    -- 
    local scores = {}
    for _, system in pairs(_systemHelper.systems()) do
        local score = 0
        for _, planet in ipairs(system.planets or {}) do
            local planetName = string.lower(planet.name or '')
            local resources = tonumber(planet.resources) or 0
            local influence = tonumber(planet.influence) or 0
            score = score + math.max(resources, influence)
            if planet.tech then
                score = score + .5
            end
            -- per planet bonus for legendaries based on personal valuing :3
            if planet.legendary == true then
                if planetName == 'primor' or planetName == 'faunus' or planetName == 'tempesta' then
                    score = score + 1 -- bad but still a goodie
                end
                elseif planetName == "hope's end" or planetName == 'garbozia' or planetName == 'industrex' or planetName == 'emelpar' then
                    score = score + 2 -- industrex and emelpare are probs like 3+ but whatever
                end                
            end
        end
        for _, anomaly in ipairs(system.anomalies or {}) do
            local name = string.lower(tostring(anomaly))
            if name:find('entropic', 1, true) and name:find('scar', 1, true) then
                score = score + 2
                break
            end
        end
        if score % 2 == 1 then -- rounddown if .5
            score = score - .5
        end
        if system.tile then
            table.insert(scores, { system.tile, score })
        end
    end
    table.sort(scores, function(a, b)
        return a[1] < b[1]
    end)
    return scores
end

function buildSlices(numSlices, ecoOption)
-- settings on back ?!?

    if ecoOption == "rich" then
        local scoreRange = { 6, 14 }
    elseif ecoOption == "poor" then
        local scoreRange = { 3, 6 }
    else -- default normal eco
        local scoreRange = { 4, 10 }
    end
     
    

    for i = 1, numSlices do --for each Slice
        local targetScore = math.random(scoreRange[1], scoreRange[2]) -- from 4-10 
        -- get desired slice value to reach if possible if not round down
        newSlice = getTiles(targetSliceScore)
    end



end

function buildSeats()
-- settings on back, but also fixed seat being playerCount



end

function getTiles(targetSliceScore)
    local targetScore = 0
    -- do middle first
    for i=1, 3 do -- for each tile in slice/seat
        -- calc from remaining score each tiles value
        tileValue = math.random(-2, 8)
        if i == 1 then
            if -- if tile is gravRift/Nebula/Nova subtract points
        findTile(score) -- pick middle tile -- extra math?
    end
end



function findTile(remainScore, )
    -- find closest scoring tile to match
    -- find tile takes desired score, returns tile ID - then detract from remainingScore

end




local _reds = SystemTiles.getRedTiles()
local reds = {} for _,each in ipairs(_reds or {}) do reds[each] = true end
for each,_ in pairs(included) do
    --Verify tile types so no misc items in the bags (like misplaced hyperlanes) are included
    if systems[each] then
        if reds[systems[each].tile] then
            if usePurpleTiles and systems[each].planets and #systems[each].planets > 0 then
                assignTier(systems[each])
            elseif AutoTier.reds then --Save which reds are actually available
                table.insert(AutoTier.reds, systems[each].tile)
            end
        elseif systems[each].planets and not (systems[each].home or systems[each].hyperlane or systems[each].faction or systems[each].fracture) then
            assignTier(systems[each])
        else print("An invalid tile was in a Red or Blue bag: guid:", each,", tile:",systems[each].tile)
        end

    end
end














-- Build fair cores and slices - core is closer to rex and slices are home portions
-- deal TF Scards as reminders of speaker pick order after draft - or the tokens generated from milty

-- options:
-- stupid home system event
-- rich/poor/normal eco
-- slice #
-- faction #






 -------------------------------------------------------------------------------













SliceTokens = {}

--- Create a single object with the home system (grey) and slice tiles,
-- merging tiles into it as child objects.  The overall slice has a safe guid.
function SliceTokens.spawn(tiles, name, label, labelColor, position, rotation)
    assert(type(tiles) == 'table')
    assert(type(name) == 'string')
    assert(type(label) == 'string')
    assert(type(position) == 'table')
    assert(type(rotation) == 'table')

    local spawnRotation = { x = 0, y = 180, z = 0 }
    local scale = { x = 1.4, y = 1, z = 1.4 }  -- removes gutter

    -- Use a grid aligned position, move to requested position later
    -- (getTilePosition forces grid alignment).
    local positionGrid = Slice._getTilePosition(0, position, false)

    -- Place a anchor at center so rotation feels natural.
    -- Bury anchor inside other objects.  Do not use the center tile, because
    -- want to make sure have a unique GUID (not shared with a system tile).
    local anchor = SliceTokens._spawnHex(positionGrid, spawnRotation, false)
    anchor.setScale({ x = 1, y = 0.5, z = 1 })
    anchor.use_grid = false
    anchor.use_snap_points = true
    if name then
        anchor.setName(name)
    end

    -- Home system is "south" of center by one grid unit.
    local homePos = {
        x = positionGrid.x,
        y = positionGrid.y,
        z = positionGrid.z - 6.06
    }

    -- Label gets dropped when attaching, place label on anchor later.
    local home = SliceTokens._spawnHex(homePos, spawnRotation, false)
    home.setScale(scale)
    home.addTag('DELETED_ITEMS_IGNORE')
    anchor.addAttachment(home)

    for i, tile in ipairs(tiles) do
        if tile > 0 then
            local tilePos = Slice._getTilePosition(i, homePos, false)
            local tileObject = SliceTokens._cloneSystemTile(tile, tilePos, spawnRotation)
            tileObject.setScale(scale)
            tileObject.addTag('DELETED_ITEMS_IGNORE')
            anchor.addAttachment(tileObject)
        end
    end

    if label then
        anchor.createButton({
            click_function = 'doNothing',
            function_owner = self,
            label          = label,
            position       = { x = 0, y = 0.31, z = 6.75 },
            rotation       = { x = 0, y = 0, z = 0 },
            scale          = { x = 1, y = 1, z = 1 },
            width          = 0,
            height         = 0,
            font_size      = 600,
            font_color     = labelColor or 'White',
        })
    end

    anchor.setPosition(position)
    anchor.setRotation(rotation)
    return anchor
end

function SliceTokens._spawnHex(position, rotation, label)
    assert(type(position) == 'table')
    assert(type(rotation) == 'table')
    assert((not label) or type(label) == 'string')

    local params = {
        mesh = 'https://steamusercontent-a.akamaihd.net/ugc/1495712136739988324/528952D008E642AAC461C7B53CFD1CBE16C62F15/',
        collider = 'https://steamusercontent-a.akamaihd.net/ugc/1495712136739988406/0EF61A7C53392D9A4F95900FE7274EF978D24B84/',
        type = 0,
        material = 3,  -- cardboard
    }
    local hex = spawnObject({
        type              = 'Custom_Model',
        position          = position,
        rotation          = rotation,
        scale             = { x = 1.36, y = 2, z = 1.36 },
        params            = params,
        sound             = false,
        snap_to_grid      = false
    })
    hex.setCustomObject(params)
    hex.setColorTint('Black')
    hex.use_grid = false
    hex.use_snap_points = false
    if label then
        hex.createButton({
            click_function = 'doNothing',
            function_owner = self,
            label          = label,
            position       = { x = 0, y = 1.35, z = 0 },
            rotation       = { x = 0, y = 0, z = 0 },
            scale          = { x = 1, y = 1, z = 1 },
            width          = 0,
            height         = 0,
            font_size      = 400,
            font_color     = { r = 0, g = 0, b = 0 }
        })
    end
    return hex
end

function SliceTokens._cloneSystemTile(tile, position, rotation)
    local system = _systemHelper.systemFromTile(tile)
    if not system then
        error('Spawn.tileClone: not such tile ' .. tile)
    end
    local tileData = SystemTiles._getTileData(system.guid)
    if not tileData then
        error('Spawn.tileClone: missing tile ' .. tile)
    end
    local tileObject = spawnObjectData({
        data              = tileData,
        position          = position,
        rotation          = rotation,
        scale             = { x = 1.36, y = 1.36, z = 1.36 },
        sound             = false,
        snap_to_grid      = false,
    })
    tileObject.use_grid = false
    tileObject.use_snap_points = false
    return tileObject
end

function SliceTokens.getSliceIndex(sliceToken)
    local letter = string.match(sliceToken.getName(), '^Slice (.)$')
    if letter then
        local startPos, endPos = string.find('ABCDEFGHIJKLMNOPQRSTUVWXYZ', letter)
        return startPos
    end
end

function SliceTokens.getSliceName(index)
    assert(type(index) == 'number')
    local letter = string.sub('ABCDEFGHIJKLMNOPQRSTUVWXYZ', index, index)
    return 'Slice ' .. assert(letter)
end

function SliceTokens.getAll(includeInsideSelf)
    assert(type(includeInsideSelf) == 'boolean')
    local result = {}
    for _, object in ipairs(getAllObjects()) do
        if object.tag == 'Generic' and SliceTokens.getSliceIndex(object) then
            if includeInsideSelf or (not BoundingBox.insideSelf(object)) then
                table.insert(result, object)
            end
        end
    end
    return result
end

function SliceTokens.stow()
    for _, object in ipairs(SliceTokens.getAll(true)) do
        object.addTag('DELETED_ITEMS_IGNORE')
        destroyObject(object)
    end
end

-------------------------------------------------------------------------------

SeatTokens = {
    BAG_NAME = 'Randomize Seats',
    _bagGuid = false
}

function SeatTokens._getBag() -- FIX tokens need to be tied to seat tiles
    local bag = SeatTokens._bagGuid and getObjectFromGUID(SeatTokens._bagGuid)
    if bag then
        return bag
    end
    for _, object in ipairs(getAllObjects()) do
        if object.tag == 'Bag' and object.getName() == SeatTokens.BAG_NAME then
            SeatTokens._bagGuid = object.getGUID()
            return object
        end
    end
    error('SeatTokens._getBag: missing "' .. SeatTokens.BAG_NAME .. '"')
end

function SeatTokens.moveToken(color, label, position, rotation)
    assert(type(color) == 'string')
    assert(type(label) == 'string')
    assert(type(position) == 'table')
    assert(type(rotation) == 'table')

    local token = _getByName('GoPiece', color)
    if token then
        local collide = false
        local fast = true
        token.setPositionSmooth(position, collide, fast)
        token.setRotationSmooth(rotation, collide, fast)
    else
        local bag = SeatTokens._getBag()
        for _, entry in ipairs(bag.getObjects()) do
            if entry.name == color then
                token = bag.takeObject({
                    position          = position,
                    rotation          = rotation,
                    smooth            = true,
                    guid              = entry.guid
                })
            end
        end
    end
    if not token then
        error('SeatTokens.moveToken: missing token "' .. color .. '"')
    end
    token.setScale({ x = 2.5, y = 0.5, z = 2.5 })
    if label then
        token.clearButtons()
        local fontSize = 100
        if string.len(label) < 4 then
            fontSize = 300
        end
        token.createButton({
            click_function = 'doNothing',
            function_owner = self,
            label          = label,
            position       = { x = 0, y = 0.19, z = 0 },
            rotation       = { x = 0, y = 0, z = 0 },
            scale          = { x = 1, y = 1, z = 1 },
            width          = 0,
            height         = 0,
            font_size      = fontSize,
            font_color     = { r = 0, g = 0, b = 0 }
        })
    end
    return token
end

function SeatTokens.getAll(includeInsideSelf)
    assert(type(includeInsideSelf) == 'boolean')
    local nameSet = {}
    for _, color in ipairs(_zoneHelper.zones()) do
        nameSet[color] = true
    end
    local result = {}
    for _, object in ipairs(getAllObjects()) do
        if object.tag == 'GoPiece' and nameSet[object.getName()] then
            if includeInsideSelf or (not BoundingBox.insideSelf(object)) then
                table.insert(result, object)
            end
        end
    end
    return result
end

function SeatTokens.stow()
    local bag = SeatTokens._getBag()
    for _, object in ipairs(SeatTokens.getAll(true)) do
        object.clearButtons()
        bag.putObject(object)
    end
end

-------------------------------------------------------------------------------

FactionTokens = {
    BAG_NAME = 'Pick a Faction to Play',
    _bagGuid = false
}

function FactionTokens._getBag()
    local bag = FactionTokens._bagGuid and getObjectFromGUID(FactionTokens._bagGuid)
    if bag then
        return bag
    end
    for _, object in ipairs(getAllObjects()) do
        if object.tag == 'Bag' and object.getName() == FactionTokens.BAG_NAME then
            FactionTokens._bagGuid = object.getGUID()
            return object
        end
    end
    error('FactionTokens._getBag: missing "' .. FactionTokens.BAG_NAME .. '"')
end

function FactionTokens.randomFactionNames(count)
    assert(type(count) == 'number')
    local candidates = {}
    local bag = FactionTokens._getBag()
    for _, entry in ipairs(bag.getObjects()) do
        local factionName = string.match(entry.name, '^(.*) Faction Token*')
        assert(_factionHelper.fromTokenName(factionName))
        table.insert(candidates, factionName)
    end

    local result = {}
    while #result < count do
        local i = math.random(1, #candidates)
        local factionName = table.remove(candidates, i)
        table.insert(result, factionName)
    end
    return result
end

function FactionTokens.placeToken(factionName, position, rotation)
    assert(type(factionName) == 'string')
    local faction = assert(_factionHelper.fromTokenName(factionName))
    local factionTokenName = faction.tokenName .. ' Faction Token'

    local bag = FactionTokens._getBag()
    for i, entry in ipairs(bag.getObjects()) do
        if entry.name == factionTokenName then
            local token = bag.takeObject({
                index             = entry.index,
                position          = position,
                rotation          = rotation,
                smooth            = true,
            })
            return token
        end
    end
    error('FactionTokens.placeToken: missing token "' .. factionName .. '"')
end

function FactionTokens.getAll(includeInsideSelf)
    assert(type(includeInsideSelf) == 'boolean')
    local nameSet = {}
    for _, faction in pairs(_factionHelper.allFactions(true)) do
        nameSet[faction.tokenName .. ' Faction Token'] = true
    end
    local result = {}
    for _, object in ipairs(getAllObjects()) do
        if object.tag == 'Card' and nameSet[object.getName()] then
            if includeInsideSelf or (not BoundingBox.insideSelf(object)) then
                table.insert(result, object)
            end
        end
    end
    return result
end

function FactionTokens.stow()
    local bag = FactionTokens._getBag()
    for _, object in ipairs(FactionTokens.getAll(true)) do
        bag.putObject(object)
        coroutine.yield(0) -- wait a moment to prevent deck from forming
    end
end

-------------------------------------------------------------------------------

DraftSelectionMats = {
    NAME = 'Draft Selections Mat',
    DESCRIPTION = 'Place your slice, faction, and seat draft selections here'
}

function DraftSelectionMats.stow()
    for _, object in ipairs(getAllObjects()) do
        if object.tag == 'Generic' and object.getName() == DraftSelectionMats.NAME then
            object.addTag('DELETED_ITEMS_IGNORE')
            destroyObject(object)
        end
    end
end

function DraftSelectionMats.spawn(color) -- FIX need extra slot and make positioned better
    assert(type(color) == 'string')

    local zoneAttrs = assert(_zoneHelper.zoneAttributes(color))
    local pos = {
        x = zoneAttrs.center.x,
        y = zoneAttrs.center.y + 2,
        z = zoneAttrs.center.z + 4 * (zoneAttrs.center.z < 0 and 1 or -1)
    }
    local rot = {
        x = 0,
        y = zoneAttrs.rotation.y,
        z = 0
    }
    local scale = {
        x = 1,
        y = 1,
        z = 1
    }

    local params = {
        mesh = 'https://steamusercontent-a.akamaihd.net/ugc/18297788509728276118/23FC1D77A4E2C9F34C0D5E269C3A0A7706EBB850/',
        diffuse = 'https://raw.githubusercontent.com/Somberlord/ti4-tts-assets/main/gamesetup_diffuse.jpg',
        type = 0,  -- generic
        material = 3,  -- cardboard
    }
    local tile = spawnObject({
        type              = 'Custom_Model',
        position          = pos,
        rotation          = rot,
        scale             = scale,
        callback_function = function(object) object.setLock(true) end,
        sound             = false,
        snap_to_grid      = false,
        params            = params,
    })
    tile.setCustomObject(params)
    tile.setName(DraftSelectionMats.NAME)
    tile.setDescription(DraftSelectionMats.DESCRIPTION)
    tile.use_grid = false
    tile.use_snap_points = false

    local snapPoints = {}
    local lines = {}
    local lineColor = { r = 1, g = 1, b = 1, a = 0.1 }
    for col = 0, 2 do
        for row = 1, 1 do
            table.insert(snapPoints, {
                position = Slots.getPosition(2 - col, row, Slots.SELECTION_MAT),
                rotation = { x = 0, y = 0, z = 0 },
                rotation_snap = true,
            })
            table.insert(lines, Slots.getVectorLine(col, row, Slots.SELECTION_MAT, lineColor))
        end
    end
    tile.setSnapPoints(snapPoints)
    tile.setVectorLines(lines)

    local playerName = color
    for _, player in ipairs(Player.getPlayers()) do
        if player.color == color then
            playerName = player.steam_name
            break
        end
    end
    tile.createButton({
        click_function = 'doNothing',
        function_owner = self,
        label          = playerName .. '\nDraft Choices',
        position       = Slots.getPosition(1, 0, Slots.SELECTION_MAT),
        width          = 0,
        height         = 0,
        font_size      = 400,
        font_color     = 'Yellow',
    })
end

-------------------------------------------------------------------------------

SystemTiles = {
    _tileGuidToBagGuid = false
}

function SystemTiles.getRedTiles()
    local isPoK = _setupHelper.getPoK()
    local result = {}
    for _, system in pairs(_systemHelper.systems()) do
        local isRedTile = false
        isRedTile = (system.anomalies and #system.anomalies > 0)
        isRedTile = isRedTile or (not system.planets) or (#system.planets == 0)
        if not isRedTile and system.planets then
            local onlyStations = true
            for _,each in ipairs(system.planets or {}) do
                if not each.station then onlyStations = false break end
            end
            isRedTile = onlyStations
        end
        
        if system.tile > 2000 and system.tile < 2036 then --Pick a planet systems
            isRedTile = false
        elseif system.hyperlane or system.fracture or system.home or system.faction or system.offMap then
            isRedTile = false
        end

        if isRedTile then
            table.insert(result, system.tile)
        end
    end
    return result
end

function SystemTiles._getTileBag(tileGuid)
    assert(type(tileGuid) == 'string')
    if not SystemTiles._tileGuidToBagGuid then
        SystemTiles._tileGuidToBagGuid = {}
        local guidToSystem = _systemHelper.systems()
        local bagSet = {
            ['Blue Planet Tiles'] = true,
            ['Red Anomaly Tiles'] = true,
        }
        local tileToBag = {}
        for _, object in ipairs(getAllObjects()) do
            if object.tag == 'Bag' and bagSet[object.getName()] then
                local bagGuid = object.getGUID()
                for _, entry in ipairs(object.getObjects()) do
                    if guidToSystem[entry.guid] then
                        SystemTiles._tileGuidToBagGuid[entry.guid] = bagGuid
                    end
                end
            end
        end
    end
    local bagGuid = SystemTiles._tileGuidToBagGuid[tileGuid]
    return bagGuid and getObjectFromGUID(bagGuid)
end

function SystemTiles.placeTile(tile, position, rotation)
    local system = _systemHelper.systemFromTile(tile)
    if not system then
        error('SystemTiles._placeTile: not such tile ' .. tile)
    end
    local bag = SystemTiles._getTileBag(system.guid)
    local tileObject = false
    if bag then
        tileObject = bag.takeObject({
            position          = position,
            rotation          = rotation,
            smooth            = true,
            guid              = system.guid
        })
    else
        tileObject = getObjectFromGUID(system.guid)
        if tileObject then
            local collide = false
            local fast = true
            tileObject.setPositionSmooth(position, collide, fast)
            tileObject.setRotationSmooth(rotation, collide, fast)
        end
    end
    if not tileObject then
        error('SystemTiles._placeTile: missing tile ' .. tile)
    end
    Wait.time(function() _systemHelper.lockSystemTile(system.guid) end, 3)
    return tileObject
end

function SystemTiles._getTileData(tileGuid)
    -- Find in bag (expected path).
    local bag = SystemTiles._getTileBag(tileGuid)
    if bag then
        for _, tileData in ipairs(bag.getData().ContainedObjects) do
            if tileData.GUID == tileGuid then
                return tileData
            end
        end
    end
    -- Not found in bag, look on table.
    local tileObject = getObjectFromGUID(tileGuid)
    if tileObject then
        return tileObject.getData()
    end
    error('SystemTiles._getTileData: missing tile ' .. tileGuid)
end

-------------------------------------------------------------------------------

Slice = {
    -- Slice is a mini-map string with tiles in this order.
    OFFSETS = {
        { name = 'leftOfHome', x = -1, z = 0.5 },
        { name = 'frontOfHome', x = 0, z = 1 },
        { name = 'rightOfHome', x = 1, z = 0.5 },
        { name = 'leftEquidistant', x = -1, z = 1.5 },
        { name = 'frontFurther', x = 0, z = 2 },
    }
}

--- Compute "R/I TECH LEGENDARY" label from a list of tile numbers. -- FIX
function Slice.getSummary(tiles)
    local valid = {}
    for _, tile in ipairs(tiles) do
        if tile > 0 then
            table.insert(valid, tile)
        end
    end
    return _systemHelper.summarizeTiles(valid)
end

--- Swap tiles so no anomalies are adjacent (in this slice).
function Slice.randomizeAndFixAdjacentAnomalies(tiles)
    local tiles = VolverMilty.permute(tiles)

    -- Lookup by tile number is slightly expensive (linear).
    -- Get the relevant systems in one pass.
    local tileSet = {}
    for _, tile in ipairs(tiles) do
        tileSet[tile] = true
    end
    local tileToSystem = {}
    for _, system in pairs(_systemHelper.systems()) do
        if tileSet[system.tile] then
            tileToSystem[system.tile] = system
        end
    end

    local swapRules = {
        {
            check1 = 'leftOfHome',
            check2 = 'leftEquidistant',
            swaps = {
                { 'leftOfHome', 'rightOfHome' },
                { 'leftEquidistant', 'rightOfHome' },
                { 'leftEquidistant', 'frontFurther' },
            },
        },
        {
            check1 = 'leftOfHome',
            check2 = 'frontOfHome',
            swaps = {
                { 'frontOfHome', 'frontFurther' },
                { 'frontOfHome', 'rightOfHome' },
            },
        },
        {
            check1 = 'frontOfHome',
            check2 = 'frontFurther',
            swaps = {
                { 'frontOfHome', 'leftOfHome' },
                { 'frontOfHome', 'rightOfHome' },
            },
        },
        {
            check1 = 'frontOfHome',
            check2 = 'leftEquidistant',
            swaps = {
                { 'frontOfHome', 'rightOfHome' },
            },
        },
        {
            check1 = 'frontOfHome',
            check2 = 'rightOfHome',
            swaps = {
                { 'frontOfHome', 'leftOfHome' },
                { 'frontOfHome', 'leftEquidistant' },
                { 'frontOfHome', 'frontFurther' },
            },
        },
        {
            check1 = 'leftEquidistant',
            check2 = 'frontFurther',
            swaps = {
                { 'leftEquidistant', 'leftOfHome' },
                { 'leftEquidistant', 'rightOfHome' },
                { 'frontFurther', 'rightOfHome' },
            },
        },
    }
    local nameToIndex = {}
    for i, offset in ipairs(Slice.OFFSETS) do
        nameToIndex[offset.name] = i
    end
    local function doSwaps(checkFunction)
        for _, swapRule in ipairs(swapRules) do
            local check1 = assert(tiles[nameToIndex[swapRule.check1]])
            local check2 = assert(tiles[nameToIndex[swapRule.check2]])
            local system1 = assert(tileToSystem[check1])
            local system2 = assert(tileToSystem[check2])
            if checkFunction(system1, system2) then
                local swap = assert(swapRule.swaps[math.random(1, #swapRule.swaps)])
                local index1 = assert(nameToIndex[swap[1]])
                local index2 = assert(nameToIndex[swap[2]])
                local tile1 = tiles[index1]
                local tile2 = tiles[index2]
                tiles[index1] = tile2
                tiles[index2] = tile1
            end
        end
    end

    -- Separate adjacent same wormholes.
    local function checkWormholes(system1, system2)
        assert(type(system1) == 'table' and type(system2) == 'table')
        local wormholeSet1 = {}
        for _, wormhole in ipairs(system1.wormholes or {}) do
            wormholeSet1[wormhole] = true
        end
        for _, wormhole in ipairs(system2.wormholes or {}) do
            if wormholeSet1[wormhole] then
                return true
            end
        end
    end
    doSwaps(checkWormholes)

    -- Separate adjacent anomalies (may clobber earlier adjustments).
    local function checkAnomalies(system1, system2)
        local anomalies1 = system1.anomalies and #system1.anomalies > 0
        local anomalies2 = system2.anomalies and #system2.anomalies > 0
        return anomalies1 and anomalies2
    end
    doSwaps(checkAnomalies)

    return tiles
end

--- Get position given the home system position and tile index.
-- Optionally apply slice rotation to account for map orientation.
function Slice._getTilePosition(i, p0, applyRotation)
    assert(type(i) == 'number', 'bad i')
    assert(type(p0) == 'table', 'bad p0')
    assert(type(applyRotation) == 'boolean', 'bad applyRotation')

    local offset = { x = 0, z = 0 }
    if i > 0 then
        offset = assert(Slice.OFFSETS[i])
    end

    local function getOutscribedTileRadius()
        local x = Grid.sizeX or 7
        local y = Grid.sizeY or 7
        assert(x == y, 'error: not a square grid')
        return x / 2.0
    end

    local function getInscribedTileRadius()
        local r = getOutscribedTileRadius()
        local c = r
        local b = r / 2.0
        return math.sqrt(c^2 - b^2)
    end

    -- Compute position.
    local dx = getInscribedTileRadius() * 2 * offset.x
    local dz = getInscribedTileRadius() * 2 * offset.z
    if applyRotation then
        local theta = math.atan2(p0.z, p0.x) - (math.pi / 2)
        local inverse = (theta + math.pi) % (math.pi * 2)
        local dx2 = math.cos(inverse) * dx - math.sin(inverse) * dz
        local dz2 = math.sin(inverse) * dx + math.cos(inverse) * dz
        dx, dz = dx2, dz2
    end
    local pos = {
        x = p0.x + dx,
        y = p0.y,
        z = p0.z + dz,
    }

    -- Convert to hex and back again to be certain pos is grid aligned.
    local y = pos.y
    local hex = _systemHelper.hexFromPosition(pos)
    pos = _systemHelper.hexToPosition(hex)
    pos = {
        x = pos.x,
        y = y,
        z = pos.z
    }

    return pos
end

--- Place system tiles, find tiles in bags or on table.
function Slice.placeTiles(tiles, homeSystemPosition, applyRotation)
    assert(type(tiles) == 'table')
    assert(type(homeSystemPosition) == 'table')
    assert(type(applyRotation) == 'boolean')

    for i, tile in ipairs(tiles) do
        if tile > 0 then
            local pos = Slice._getTilePosition(i, homeSystemPosition, applyRotation)
            local rot = { x = 0, y = 180, z = 0 }
            SystemTiles.placeTile(tile, pos, rot)
        end
    end
end

-------------------------------------------------------------------------------

-------------------------------------------------------------------------------

function _selectFaction(color, factionTokenName)
    assert(type(color) == 'string' and type(factionTokenName) == 'string')

    local factionSelector = false
    for _, object in ipairs(getAllObjects()) do
        local name = object.getName()
        if name == 'Faction Selector' then
            local zone = _zoneHelper.zoneFromPosition(object.getPosition())
            if zone == color then
                factionSelector = object
                break
            end
        end
    end
    assert(factionSelector, 'missing faction selector for ' .. color)

    factionSelector.call('selectFaction', factionTokenName)
end












-- grab list of blues
-- grab list of red
-- grab list of purple

-- random amount of good cores and good nuclei
-- tiles weighted as follows:
--   inf/res = i/r
--   tech skip + 1 | Blue +1.5
--   scar + 2
--   gravRift/nova - 2 if center otherwise -1


-- Build fair cores and slices - core is closer to rex and slices are home portions
-- deal TF Scards as reminders of speaker pick order after draft - or the tokens generated from milty

-- options:
 -- stupid home system event
 -- rich/poor/normal eco
 -- slice #
 -- faction #