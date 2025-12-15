local Config = require 'config'

lib.locale(Config.Locale)

local DUI_WIDTH = 512
local DUI_HEIGHT = 320
local UPDATE_INTERVAL = 100
local CHECK_INTERVAL = 200

local MARKER_HEIGHT_MAX = 350.0
local MARKER_HEIGHT_MID = 80.0
local MARKER_HEIGHT_MIN = 8.0
local HEIGHT_FAR_DISTANCE = 1000.0
local HEIGHT_MID_DISTANCE = 500.0
local HEIGHT_CLOSE_DISTANCE = 30.0
local MAX_DRAW_DISTANCE_SQ = 10000.0 * 10000.0
local ELEVATION_COMPENSATION_FACTOR = 0.6
local DISTANCE_HEIGHT_BONUS = 0.25

local FIXED_SCALE_WIDTH = 0.16
local FIXED_SCALE_HEIGHT = 0.12

local HEIGHT_LERP_SPEED = 0.04
local GROUND_Z_LERP_SPEED = 0.05

local duiObject = nil
local duiTexture = nil
local txdName = 'sd_waypoints'
local txnName = 'waypoint_marker'

local isWaypointActive = false
local waypointX, waypointY = 0.0, 0.0
local smoothedHeight = MARKER_HEIGHT_MAX
local smoothedGroundZ = 0.0
local targetHeight = MARKER_HEIGHT_MAX
local targetGroundZ = 0.0
local lastValidGroundZ = 0.0
local currentDistance = 0
local isMarkerVisible = false

local lastSentDistance = ''
local lastSentUnit = ''

local floor = math.floor
local sqrt = math.sqrt
local max = math.max
local abs = math.abs
local format = string.format

local GetGameplayCamCoord = GetGameplayCamCoord
local GetScreenCoordFromWorldCoord = GetScreenCoordFromWorldCoord
local SetDrawOrigin = SetDrawOrigin
local DrawSprite = DrawSprite
local ClearDrawOrigin = ClearDrawOrigin
local DrawLine = DrawLine
local PlayerPedId = PlayerPedId
local GetEntityCoords = GetEntityCoords
local GetFirstBlipInfoId = GetFirstBlipInfoId
local DoesBlipExist = DoesBlipExist
local GetBlipInfoIdCoord = GetBlipInfoIdCoord
local GetGroundZFor_3dCoord = GetGroundZFor_3dCoord
local CreateThread = CreateThread
local Wait = Wait

local METERS_TO_FEET = 3.28084
local METERS_TO_MILES = 0.000621371

local function CreateWaypointDUI()
    if duiObject then return end

    local url = ('nui://%s/web/build/index.html'):format(GetCurrentResourceName())
    duiObject = CreateDui(url, DUI_WIDTH, DUI_HEIGHT)

    if not duiObject then
        return print('[sd-waypoints] Failed to create DUI')
    end

    local txd = CreateRuntimeTxd(txdName)
    duiTexture = CreateRuntimeTextureFromDuiHandle(txd, txnName, GetDuiHandle(duiObject))
end

local function DestroyWaypointDUI()
    if duiObject then
        DestroyDui(duiObject)
        duiObject = nil
        duiTexture = nil
    end
end

local function SendDUIMessage(action, data)
    if duiObject then
        SendDuiMessage(duiObject, json.encode({ action = action, data = data or {} }))
    end
end

local function GetGroundZAtPosition(x, y)
    for testZ = 1000.0, 0.0, -100.0 do
        local found, z = GetGroundZFor_3dCoord(x, y, testZ, false)
        if found and z > -50.0 then
            return z
        end
    end
    return GetEntityCoords(PlayerPedId()).z
end

local function FormatDistance(distance)
    if Config.UseMetric then
        if distance >= 1000 then
            return format('%.1f', distance * 0.001), 'KM'
        end
        local m = floor(distance)
        return tostring(m > 0 and m or 0), 'M'
    else
        local feet = distance * METERS_TO_FEET
        if feet >= 5280 then
            return format('%.1f', distance * METERS_TO_MILES), 'MI'
        end
        local ft = floor(feet)
        return tostring(ft > 0 and ft or 0), 'FT'
    end
end

local function GetTargetMarkerHeight(distance, playerZ, waypointGroundZ)
    distance = max(0, distance)

    local baseHeight
    if distance >= HEIGHT_FAR_DISTANCE then
        baseHeight = MARKER_HEIGHT_MAX
    elseif distance <= HEIGHT_CLOSE_DISTANCE then
        baseHeight = MARKER_HEIGHT_MIN
    elseif distance <= HEIGHT_MID_DISTANCE then
        local t = (distance - HEIGHT_CLOSE_DISTANCE) / (HEIGHT_MID_DISTANCE - HEIGHT_CLOSE_DISTANCE)
        t = t * t * (3.0 - 2.0 * t)
        baseHeight = MARKER_HEIGHT_MIN + (MARKER_HEIGHT_MID - MARKER_HEIGHT_MIN) * t
    else
        local t = (distance - HEIGHT_MID_DISTANCE) / (HEIGHT_FAR_DISTANCE - HEIGHT_MID_DISTANCE)
        t = t * t * (3.0 - 2.0 * t)
        baseHeight = MARKER_HEIGHT_MID + (MARKER_HEIGHT_MAX - MARKER_HEIGHT_MID) * t
    end

    local distanceBonus = distance > HEIGHT_FAR_DISTANCE and (distance - HEIGHT_FAR_DISTANCE) * DISTANCE_HEIGHT_BONUS or 0.0
    local elevationDiff = playerZ - waypointGroundZ
    local elevationBonus = elevationDiff > 0 and elevationDiff * ELEVATION_COMPENSATION_FACTOR or 0.0

    return baseHeight + distanceBonus + elevationBonus
end

local function StartWaypointThread()
    CreateThread(function()
        while true do
            local blip = GetFirstBlipInfoId(8)

            if DoesBlipExist(blip) then
                local blipCoords = GetBlipInfoIdCoord(blip)
                local bx, by = blipCoords.x, blipCoords.y

                if not isWaypointActive then
                    isWaypointActive = true
                    waypointX, waypointY = bx, by

                    local initialGroundZ = GetGroundZAtPosition(bx, by)
                    targetGroundZ = initialGroundZ
                    smoothedGroundZ = initialGroundZ
                    lastValidGroundZ = initialGroundZ
                    targetHeight = MARKER_HEIGHT_MAX
                    smoothedHeight = MARKER_HEIGHT_MAX

                    SendDUIMessage('show')
                elseif bx ~= waypointX or by ~= waypointY then
                    waypointX, waypointY = bx, by
                    local newGroundZ = GetGroundZAtPosition(bx, by)
                    if newGroundZ > -50.0 then
                        targetGroundZ = newGroundZ
                        lastValidGroundZ = newGroundZ
                    end
                end
            elseif isWaypointActive then
                isWaypointActive = false
                waypointX, waypointY = 0.0, 0.0
                lastSentDistance = ''
                lastSentUnit = ''
                SendDUIMessage('hide')
            end

            Wait(CHECK_INTERVAL)
        end
    end)
end

local function StartDistanceThread()
    CreateThread(function()
        while true do
            if isWaypointActive then
                local playerCoords = GetEntityCoords(PlayerPedId())
                local dx, dy = playerCoords.x - waypointX, playerCoords.y - waypointY
                currentDistance = sqrt(dx * dx + dy * dy)
                targetHeight = GetTargetMarkerHeight(currentDistance, playerCoords.z, targetGroundZ)

                if isMarkerVisible then
                    local distValue, distUnit = FormatDistance(currentDistance)
                    if distValue ~= lastSentDistance or distUnit ~= lastSentUnit then
                        lastSentDistance = distValue
                        lastSentUnit = distUnit
                        SendDUIMessage('updateDistance', { distance = distValue, unit = distUnit })
                    end
                end
            end

            Wait(UPDATE_INTERVAL)
        end
    end)
end

local function StartGroundZUpdateThread()
    CreateThread(function()
        while true do
            if isWaypointActive then
                local newGroundZ = GetGroundZAtPosition(waypointX, waypointY)
                if newGroundZ > -50.0 and abs(newGroundZ - lastValidGroundZ) > 0.5 then
                    targetGroundZ = newGroundZ
                    lastValidGroundZ = newGroundZ
                end
            end
            Wait(1500)
        end
    end)
end

local function StartRenderThread()
    local maxHeightClamped = MARKER_HEIGHT_MAX + 1000.0
    local wpX, wpY, groundZ, markerZ
    local camCoords, dx, dy, dz, camDistSq, camDist, distMult
    local spriteWorldHeight, arrowTipZ

    CreateThread(function()
        while true do
            if isWaypointActive then
                smoothedHeight = smoothedHeight + (targetHeight - smoothedHeight) * HEIGHT_LERP_SPEED
                smoothedGroundZ = smoothedGroundZ + (targetGroundZ - smoothedGroundZ) * GROUND_Z_LERP_SPEED

                if smoothedHeight < MARKER_HEIGHT_MIN then
                    smoothedHeight = MARKER_HEIGHT_MIN
                elseif smoothedHeight > maxHeightClamped then
                    smoothedHeight = maxHeightClamped
                end

                wpX, wpY = waypointX, waypointY
                groundZ = smoothedGroundZ
                markerZ = groundZ + smoothedHeight

                camCoords = GetGameplayCamCoord()
                dx, dy, dz = wpX - camCoords.x, wpY - camCoords.y, markerZ - camCoords.z
                camDistSq = dx * dx + dy * dy + dz * dz

                if camDistSq < MAX_DRAW_DISTANCE_SQ and GetScreenCoordFromWorldCoord(wpX, wpY, markerZ) then
                    camDist = sqrt(camDistSq)
                    distMult = camDist > 500.0 and (1.0 + (camDist - 500.0) * 0.0001) or 1.0

                    SetDrawOrigin(wpX, wpY, markerZ, 0)
                    DrawSprite(txdName, txnName, 0.0, 0.0, FIXED_SCALE_WIDTH * distMult, FIXED_SCALE_HEIGHT * distMult, 0.0, 255, 255, 255, 255)
                    ClearDrawOrigin()

                    spriteWorldHeight = FIXED_SCALE_HEIGHT * distMult * camDist * 1.2
                    arrowTipZ = markerZ - (spriteWorldHeight * 0.18)
                    if arrowTipZ < groundZ + 0.5 then
                        arrowTipZ = groundZ + 0.5
                    end
                    DrawLine(wpX, wpY, groundZ, wpX, wpY, arrowTipZ, 255, 255, 255, 255)

                    isMarkerVisible = true
                else
                    isMarkerVisible = false
                end

                Wait(0)
            else
                isMarkerVisible = false
                Wait(500)
            end
        end
    end)
end

local function Initialize()
    CreateWaypointDUI()
    Wait(500)
    SendDUIMessage('config', {
        color = Config.Color,
        label = locale('waypoint'),
        style = Config.Style or 'classic'
    })
    SendDUIMessage('hide')

    StartWaypointThread()
    StartDistanceThread()
    StartGroundZUpdateThread()
    StartRenderThread()
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
