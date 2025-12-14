local DUI_WIDTH = 512
local DUI_HEIGHT = 320
local UPDATE_INTERVAL = 50 -- ms between distance updates
local CHECK_INTERVAL = 200 -- ms between waypoint checks

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
    -- Try the native function from multiple heights
    for testZ = 1000.0, 0.0, -100.0 do
        local found, z = GetGroundZFor_3dCoord(x, y, testZ, false)
        if found and z > -50.0 then
            return z
        end
    end

    -- Fallback: use player's Z as reference
    local playerCoords = GetEntityCoords(PlayerPedId())
    return playerCoords.z
end

--- Gets the waypoint blip info
---@return number|nil blip The blip handle
---@return vector3|nil coords The waypoint coordinates
local function GetWaypointInfo()
    local blip = GetFirstBlipInfoId(8) -- 8 = waypoint blip sprite

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
    return math.sqrt(dx * dx + dy * dy)
end

--- Formats distance for display
---@param distance number Distance in meters
---@return string value The formatted distance value
---@return string unit The unit (M or KM)
local function FormatDistance(distance)
    if distance >= 1000 then
        return string.format('%.1f', distance / 1000), 'KM'
    else
        return string.format('%d', math.floor(math.max(0, distance))), 'M'
    end
end

--- Calculates target marker height based on distance and elevation with smooth curve
---@param distance number Distance to waypoint
---@param playerZ number Player's Z coordinate
---@param waypointGroundZ number Waypoint's ground Z coordinate
---@return number height The target height offset for the marker
local function GetTargetMarkerHeight(distance, playerZ, waypointGroundZ)
    -- Clamp distance to valid range
    distance = math.max(0, distance)

    local baseHeight
    if distance >= HEIGHT_FAR_DISTANCE then
        -- Very far - use max height plus distance bonus
        baseHeight = MARKER_HEIGHT_MAX
    elseif distance <= HEIGHT_CLOSE_DISTANCE then
        -- Very close - use min height
        baseHeight = MARKER_HEIGHT_MIN
    elseif distance <= HEIGHT_MID_DISTANCE then
        -- Close to mid range: interpolate from MIN to MID
        local range = HEIGHT_MID_DISTANCE - HEIGHT_CLOSE_DISTANCE
        local t = (distance - HEIGHT_CLOSE_DISTANCE) / range
        t = t * t * (3.0 - 2.0 * t) -- smoothstep
        baseHeight = MARKER_HEIGHT_MIN + (MARKER_HEIGHT_MID - MARKER_HEIGHT_MIN) * t
    else
        -- Mid to far range: interpolate from MID to MAX
        local range = HEIGHT_FAR_DISTANCE - HEIGHT_MID_DISTANCE
        local t = (distance - HEIGHT_MID_DISTANCE) / range
        t = t * t * (3.0 - 2.0 * t) -- smoothstep
        baseHeight = MARKER_HEIGHT_MID + (MARKER_HEIGHT_MAX - MARKER_HEIGHT_MID) * t
    end

    -- Add extra height based on distance (so very far markers appear higher in sky)
    local distanceBonus = 0.0
    if distance > HEIGHT_FAR_DISTANCE then
        distanceBonus = (distance - HEIGHT_FAR_DISTANCE) * DISTANCE_HEIGHT_BONUS
    end

    -- Compensate for elevation difference (if player is higher than waypoint)
    local elevationDiff = playerZ - waypointGroundZ
    local elevationBonus = 0.0
    if elevationDiff > 0 then
        -- Player is higher - add extra height so marker appears in sky
        elevationBonus = elevationDiff * ELEVATION_COMPENSATION_FACTOR
    end

    return baseHeight + distanceBonus + elevationBonus
end

--- Draws the waypoint marker in 3D space with fixed screen size
---@param worldX number World X coordinate
---@param worldY number World Y coordinate
---@param worldZ number World Z coordinate
---@return number distanceMultiplier The distance multiplier used for scaling
local function DrawWaypointMarker3D(worldX, worldY, worldZ)
    if not duiTexture then return 1.0 end

    -- Calculate distance for visibility and scaling
    local camCoords = GetGameplayCamCoord()
    local distance = #(camCoords - vector3(worldX, worldY, worldZ))

    if distance > MAX_DRAW_DISTANCE then return 1.0 end

    -- Check if on screen (for culling only)
    local onScreen = GetScreenCoordFromWorldCoord(worldX, worldY, worldZ)
    if not onScreen then return 1.0 end

    -- Use fixed screen size so marker is always readable
    -- Slightly increase size at very far distances for visibility
    local distanceMultiplier = 1.0
    if distance > 500.0 then
        distanceMultiplier = 1.0 + ((distance - 500.0) / 5000.0) * 0.5
    end

    local width = FIXED_SCALE_WIDTH * distanceMultiplier
    local height = FIXED_SCALE_HEIGHT * distanceMultiplier

    -- Use SetDrawOrigin for synchronized 3D positioning (no frame delay)
    SetDrawOrigin(worldX, worldY, worldZ, 0)
    DrawSprite(txdName, txnName, 0.0, 0.0, width, height, 0.0, 255, 255, 255, 255)
    ClearDrawOrigin()

    return distanceMultiplier
end

--- Draws a vertical line from ground to the arrow tip
---@param groundX number
---@param groundY number
---@param groundZ number
---@param markerZ number
local function DrawVerticalLine(groundX, groundY, groundZ, markerZ)
    local camCoords = GetGameplayCamCoord()
    local camDist = #(camCoords - vector3(groundX, groundY, markerZ))

    -- Calculate distance multiplier (same as used for sprite scaling)
    local distanceMultiplier = 1.0
    if camDist > 500.0 then
        distanceMultiplier = 1.0 + ((camDist - 500.0) / 5000.0) * 0.5
    end

    -- The sprite is drawn centered at markerZ with height = FIXED_SCALE_HEIGHT * distanceMultiplier
    -- Convert screen-space height to world-space height (approximate)
    -- Screen height * distance * FOV factor
    local spriteWorldHeight = FIXED_SCALE_HEIGHT * distanceMultiplier * camDist * 1.2

    -- Arrow tip is at the very bottom of the sprite
    -- Sprite is centered, so bottom is at markerZ - (spriteWorldHeight / 2)
    local arrowTipZ = markerZ - (spriteWorldHeight * 0.18)

    -- Make sure line end is above ground
    if arrowTipZ < groundZ + 0.5 then
        arrowTipZ = groundZ + 0.5
    end

    -- Draw the line from ground to arrow tip
    DrawLine(
        groundX, groundY, groundZ,
        groundX, groundY, arrowTipZ,
        255, 255, 255, 255
    )
end

--- Main thread for tracking waypoint changes
local function StartWaypointThread()
    CreateThread(function()
        while true do
            local blip, coords = GetWaypointInfo()

            if blip and coords then
                if not isWaypointActive then
                    -- Waypoint was just set
                    isWaypointActive = true
                    waypointBlip = blip
                    waypointCoords = coords

                    -- Get initial ground Z
                    local initialGroundZ = GetGroundZAtPosition(coords.x, coords.y)
                    targetGroundZ = initialGroundZ
                    smoothedGroundZ = initialGroundZ
                    lastValidGroundZ = initialGroundZ

                    -- Start at max height
                    targetHeight = MARKER_HEIGHT_MAX
                    smoothedHeight = MARKER_HEIGHT_MAX

                    SendDUIMessage('show')
                elseif coords.x ~= waypointCoords.x or coords.y ~= waypointCoords.y then
                    -- Waypoint position changed
                    waypointCoords = coords
                    local newGroundZ = GetGroundZAtPosition(coords.x, coords.y)
                    if newGroundZ > -50.0 then
                        targetGroundZ = newGroundZ
                        lastValidGroundZ = newGroundZ
                    end
                end
            elseif isWaypointActive then
                -- Waypoint was removed
                isWaypointActive = false
                waypointBlip = nil
                waypointCoords = nil
                SendDUIMessage('hide')
            end

            Wait(CHECK_INTERVAL)
        end
    end)
end

--- Thread for updating the distance display
local function StartDistanceThread()
    CreateThread(function()
        while true do
            if isWaypointActive and waypointCoords then
                local playerCoords = GetEntityCoords(PlayerPedId())
                currentDistance = CalculateDistance2D(playerCoords, waypointCoords)
                local distValue, distUnit = FormatDistance(currentDistance)

                SendDUIMessage('updateDistance', {
                    distance = distValue,
                    unit = distUnit
                })

                -- Update target height based on distance and elevation
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
                -- Only update if we found valid ground
                if newGroundZ > -50.0 then
                    -- Only update target if significantly different (reduces jitter)
                    if math.abs(newGroundZ - lastValidGroundZ) > 0.5 then
                        targetGroundZ = newGroundZ
                        lastValidGroundZ = newGroundZ
                    end
                end
            end
            Wait(1500) -- Check less frequently
        end
    end)
end

--- Main render thread for drawing the marker
local function StartRenderThread()
    CreateThread(function()
        while true do
            if isWaypointActive and waypointCoords then
                -- Smooth the height transition
                smoothedHeight = Lerp(smoothedHeight, targetHeight, HEIGHT_LERP_SPEED)

                -- Smooth the ground Z transition
                smoothedGroundZ = Lerp(smoothedGroundZ, targetGroundZ, GROUND_Z_LERP_SPEED)

                -- Clamp smoothed height to valid range (allow higher for distance/elevation bonus)
                smoothedHeight = Clamp(smoothedHeight, MARKER_HEIGHT_MIN, MARKER_HEIGHT_MAX + 1000.0)

                -- Calculate marker position
                local markerZ = smoothedGroundZ + smoothedHeight

                -- Draw the 3D marker
                DrawWaypointMarker3D(waypointCoords.x, waypointCoords.y, markerZ)

                -- Draw the vertical line from ground to arrow tip
                DrawVerticalLine(waypointCoords.x, waypointCoords.y, smoothedGroundZ, markerZ)

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
