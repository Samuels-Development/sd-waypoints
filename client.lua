local Config = require 'config'

lib.locale(Config.Locale)

local DUI_WIDTH = 512
local DUI_HEIGHT = 320
local UPDATE_INTERVAL = 100 -- Reduced frequency for better performance
local CHECK_INTERVAL = 200

-- Dynamic height settings - marker lowers as you get closer
local MARKER_HEIGHT_MAX = 350.0 -- Base height when very far (1km+)
local MARKER_HEIGHT_MID = 80.0 -- Height at mid range (500m)
local MARKER_HEIGHT_MIN = 8.0 -- Height when very close (under 30m)
local HEIGHT_FAR_DISTANCE = 1000.0 -- Distance where max height is used
local HEIGHT_MID_DISTANCE = 500.0 -- Distance for mid-range height
local HEIGHT_CLOSE_DISTANCE = 30.0 -- Distance where min height is used
local MAX_DRAW_DISTANCE = 10000.0 -- Maximum distance to draw the marker
local ELEVATION_COMPENSATION_FACTOR = 0.6 -- How much to compensate for elevation differences
local DISTANCE_HEIGHT_BONUS = 0.25 -- Extra height per meter of distance beyond far

-- Scale settings - marker maintains consistent apparent size
local FIXED_SCALE_WIDTH = 0.16 -- Fixed width on screen
local FIXED_SCALE_HEIGHT = 0.12 -- Fixed height on screen

-- Smoothing settings
local HEIGHT_LERP_SPEED = 0.04 -- How fast height adjusts (lower = smoother)
local GROUND_Z_LERP_SPEED = 0.05 -- How fast ground Z adjusts

local duiObject = nil
local duiHandle = nil
local duiTexture = nil
local txdName = 'sd_waypoints'
local txnName = 'waypoint_marker'
local waypointCoords = nil
local waypointBlip = nil
local isWaypointActive = false
local currentDistance = 0

-- Smoothed values
local smoothedHeight = MARKER_HEIGHT_MAX
local smoothedGroundZ = 0.0
local targetHeight = MARKER_HEIGHT_MAX
local targetGroundZ = 0.0
local lastValidGroundZ = 0.0

-- Cache for DUI updates (avoid sending when unchanged)
local lastSentDistance = ''
local lastSentUnit = ''

--- Lerp function for smooth transitions
---@param current number Current value
---@param target number Target value
---@param t number Interpolation factor (0-1)
---@return number Interpolated value
local function Lerp(current, target, t)
    return current + (target - current) * t
end

--- Clamp a value between min and max
---@param value number
---@param min number
---@param max number
---@return number
local function Clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

--- Creates the DUI browser and runtime texture
local function CreateWaypointDUI()
    if duiObject then return end

    local resourceName = GetCurrentResourceName()
    local url = string.format('nui://%s/web/build/index.html', resourceName)

    duiObject = CreateDui(url, DUI_WIDTH, DUI_HEIGHT)

    if not duiObject then
        print('[sd-waypoints] Failed to create DUI')
        return
    end

    duiHandle = GetDuiHandle(duiObject)

    local txd = CreateRuntimeTxd(txdName)
    duiTexture = CreateRuntimeTextureFromDuiHandle(txd, txnName, duiHandle)

    print('[sd-waypoints] DUI created successfully')
end

--- Destroys the DUI browser
local function DestroyWaypointDUI()
    if duiObject then
        DestroyDui(duiObject)
        duiObject = nil
        duiHandle = nil
        duiTexture = nil
    end
end

--- Sends a message to the DUI browser
---@param action string The action type
---@param data table|nil Optional data to send
local function SendDUIMessage(action, data)
    if not duiObject then return end

    local message = json.encode({
        action = action,
        data = data or {}
    })

    SendDuiMessage(duiObject, message)
end

--- Gets the ground Z coordinate at a position
---@param x number
---@param y number
---@return number groundZ The ground Z coordinate
local function GetGroundZAtPosition(x, y)
    for testZ = 1000.0, 0.0, -100.0 do
        local found, z = GetGroundZFor_3dCoord(x, y, testZ, false)
        if found and z > -50.0 then
            return z
        end
    end

    local playerCoords = GetEntityCoords(PlayerPedId())
    return playerCoords.z
end

--- Gets the waypoint blip info
---@return number|nil blip The blip handle
---@return vector3|nil coords The waypoint coordinates
local function GetWaypointInfo()
    local blip = GetFirstBlipInfoId(8)

    if not DoesBlipExist(blip) then
        return nil, nil
    end

    local blipCoords = GetBlipInfoIdCoord(blip)

    return blip, vector3(blipCoords.x, blipCoords.y, 0.0)
end

--- Calculates 2D distance between two points (ignoring Z)
---@param pos1 vector3
---@param pos2 vector3
---@return number
local function CalculateDistance2D(pos1, pos2)
    local dx = pos1.x - pos2.x
    local dy = pos1.y - pos2.y
    return sqrt(dx * dx + dy * dy)
end

local METERS_TO_FEET = 3.28084
local METERS_TO_MILES = 0.000621371

-- Localize frequently used functions for performance
local floor = math.floor
local sqrt = math.sqrt
local max = math.max
local abs = math.abs
local format = string.format

--- Formats distance for display
---@param distance number Distance in meters
---@return string value The formatted distance value
---@return string unit The unit
local function FormatDistance(distance)
    if Config.UseMetric then
        if distance >= 1000 then
            return format('%.1f', distance * 0.001), 'KM'
        else
            local m = floor(distance)
            return tostring(m > 0 and m or 0), 'M'
        end
    else
        local feet = distance * METERS_TO_FEET
        if feet >= 5280 then
            return format('%.1f', distance * METERS_TO_MILES), 'MI'
        else
            local ft = floor(feet)
            return tostring(ft > 0 and ft or 0), 'FT'
        end
    end
end

--- Calculates target marker height based on distance and elevation with smooth curve
---@param distance number Distance to waypoint
---@param playerZ number Player's Z coordinate
---@param waypointGroundZ number Waypoint's ground Z coordinate
---@return number height The target height offset for the marker
local function GetTargetMarkerHeight(distance, playerZ, waypointGroundZ)
    distance = max(0, distance)

    local baseHeight
    if distance >= HEIGHT_FAR_DISTANCE then
        baseHeight = MARKER_HEIGHT_MAX
    elseif distance <= HEIGHT_CLOSE_DISTANCE then
        baseHeight = MARKER_HEIGHT_MIN
    elseif distance <= HEIGHT_MID_DISTANCE then
        local range = HEIGHT_MID_DISTANCE - HEIGHT_CLOSE_DISTANCE
        local t = (distance - HEIGHT_CLOSE_DISTANCE) / range
        t = t * t * (3.0 - 2.0 * t)
        baseHeight = MARKER_HEIGHT_MIN + (MARKER_HEIGHT_MID - MARKER_HEIGHT_MIN) * t
    else
        local range = HEIGHT_FAR_DISTANCE - HEIGHT_MID_DISTANCE
        local t = (distance - HEIGHT_MID_DISTANCE) / range
        t = t * t * (3.0 - 2.0 * t)
        baseHeight = MARKER_HEIGHT_MID + (MARKER_HEIGHT_MAX - MARKER_HEIGHT_MID) * t
    end

    local distanceBonus = 0.0
    if distance > HEIGHT_FAR_DISTANCE then
        distanceBonus = (distance - HEIGHT_FAR_DISTANCE) * DISTANCE_HEIGHT_BONUS
    end

    local elevationDiff = playerZ - waypointGroundZ
    local elevationBonus = 0.0
    if elevationDiff > 0 then
        elevationBonus = elevationDiff * ELEVATION_COMPENSATION_FACTOR
    end

    return baseHeight + distanceBonus + elevationBonus
end

-- Pre-computed squared max distance for early exit check
local MAX_DRAW_DISTANCE_SQ = MAX_DRAW_DISTANCE * MAX_DRAW_DISTANCE

--- Draws the waypoint marker and vertical line in 3D space
---@param worldX number World X coordinate
---@param worldY number World Y coordinate
---@param groundZ number Ground Z coordinate
---@param markerZ number Marker Z coordinate (ground + height offset)
local function DrawWaypointMarker3D(worldX, worldY, groundZ, markerZ)
    if not duiTexture then return end

    local camCoords = GetGameplayCamCoord()
    local dx, dy, dz = worldX - camCoords.x, worldY - camCoords.y, markerZ - camCoords.z
    local camDistSq = dx * dx + dy * dy + dz * dz

    -- Early exit if too far (compare squared distances to avoid sqrt)
    if camDistSq > MAX_DRAW_DISTANCE_SQ then return end

    -- Check if on screen before doing more work
    if not GetScreenCoordFromWorldCoord(worldX, worldY, markerZ) then return end

    -- Calculate distance multiplier for scaling (only compute sqrt when needed)
    local camDist = sqrt(camDistSq)
    local distanceMultiplier = camDist > 500.0 and (1.0 + (camDist - 500.0) * 0.0001) or 1.0

    -- Draw the sprite
    SetDrawOrigin(worldX, worldY, markerZ, 0)
    DrawSprite(txdName, txnName, 0.0, 0.0, FIXED_SCALE_WIDTH * distanceMultiplier, FIXED_SCALE_HEIGHT * distanceMultiplier, 0.0, 255, 255, 255, 255)
    ClearDrawOrigin()

    -- Draw vertical line from ground to arrow tip
    local spriteWorldHeight = FIXED_SCALE_HEIGHT * distanceMultiplier * camDist * 1.2
    local arrowTipZ = markerZ - (spriteWorldHeight * 0.18)
    if arrowTipZ < groundZ + 0.5 then
        arrowTipZ = groundZ + 0.5
    end
    DrawLine(worldX, worldY, groundZ, worldX, worldY, arrowTipZ, 255, 255, 255, 255)
end

--- Main thread for tracking waypoint changes
local function StartWaypointThread()
    CreateThread(function()
        while true do
            local blip, coords = GetWaypointInfo()

            if blip and coords then
                if not isWaypointActive then
                    isWaypointActive = true
                    waypointBlip = blip
                    waypointCoords = coords

                    local initialGroundZ = GetGroundZAtPosition(coords.x, coords.y)
                    targetGroundZ = initialGroundZ
                    smoothedGroundZ = initialGroundZ
                    lastValidGroundZ = initialGroundZ

                    targetHeight = MARKER_HEIGHT_MAX
                    smoothedHeight = MARKER_HEIGHT_MAX

                    SendDUIMessage('show')
                elseif coords.x ~= waypointCoords.x or coords.y ~= waypointCoords.y then
                    waypointCoords = coords
                    local newGroundZ = GetGroundZAtPosition(coords.x, coords.y)
                    if newGroundZ > -50.0 then
                        targetGroundZ = newGroundZ
                        lastValidGroundZ = newGroundZ
                    end
                end
            elseif isWaypointActive then
                isWaypointActive = false
                waypointBlip = nil
                waypointCoords = nil
                lastSentDistance = ''
                lastSentUnit = ''
                SendDUIMessage('hide')
            end

            Wait(CHECK_INTERVAL)
        end
    end)
end

--- Thread for updating the distance display
local function StartDistanceThread()
    CreateThread(function()
        local playerPed
        local playerCoords
        local distValue, distUnit

        while true do
            if isWaypointActive and waypointCoords then
                playerPed = PlayerPedId()
                playerCoords = GetEntityCoords(playerPed)

                -- Calculate distance inline to avoid function call overhead
                local dx = playerCoords.x - waypointCoords.x
                local dy = playerCoords.y - waypointCoords.y
                currentDistance = sqrt(dx * dx + dy * dy)

                distValue, distUnit = FormatDistance(currentDistance)

                -- Only send DUI message if values changed
                if distValue ~= lastSentDistance or distUnit ~= lastSentUnit then
                    lastSentDistance = distValue
                    lastSentUnit = distUnit
                    SendDUIMessage('updateDistance', {
                        distance = distValue,
                        unit = distUnit
                    })
                end

                targetHeight = GetTargetMarkerHeight(currentDistance, playerCoords.z, targetGroundZ)
            end

            Wait(UPDATE_INTERVAL)
        end
    end)
end

--- Thread for continuously updating ground Z (for areas that load in)
local function StartGroundZUpdateThread()
    CreateThread(function()
        while true do
            if isWaypointActive and waypointCoords then
                local newGroundZ = GetGroundZAtPosition(waypointCoords.x, waypointCoords.y)
                if newGroundZ > -50.0 then
                    if abs(newGroundZ - lastValidGroundZ) > 0.5 then
                        targetGroundZ = newGroundZ
                        lastValidGroundZ = newGroundZ
                    end
                end
            end
            Wait(1500)
        end
    end)
end

--- Main render thread for drawing the marker
local function StartRenderThread()
    local maxHeightClamped = MARKER_HEIGHT_MAX + 1000.0

    CreateThread(function()
        while true do
            if isWaypointActive and waypointCoords then
                -- Inline lerp for height
                smoothedHeight = smoothedHeight + (targetHeight - smoothedHeight) * HEIGHT_LERP_SPEED

                -- Inline lerp for ground Z
                smoothedGroundZ = smoothedGroundZ + (targetGroundZ - smoothedGroundZ) * GROUND_Z_LERP_SPEED

                -- Inline clamp
                if smoothedHeight < MARKER_HEIGHT_MIN then
                    smoothedHeight = MARKER_HEIGHT_MIN
                elseif smoothedHeight > maxHeightClamped then
                    smoothedHeight = maxHeightClamped
                end

                -- Draw marker and line
                DrawWaypointMarker3D(waypointCoords.x, waypointCoords.y, smoothedGroundZ, smoothedGroundZ + smoothedHeight)

                Wait(0)
            else
                Wait(500)
            end
        end
    end)
end

--- Initialize the waypoint system
local function Initialize()
    CreateWaypointDUI()
    Wait(500)
    SendDUIMessage('config', {
        color = Config.Color,
        label = locale('waypoint')
    })
    SendDUIMessage('hide')

    StartWaypointThread()
    StartDistanceThread()
    StartGroundZUpdateThread()
    StartRenderThread()

    print('[sd-waypoints] Initialized')
end

CreateThread(function()
    Wait(1000)
    Initialize()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        DestroyWaypointDUI()
    end
end)
