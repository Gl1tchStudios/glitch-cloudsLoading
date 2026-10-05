local SWITCH_TYPE_LONG = 1
local SWITCH_STATE_IN_SKY = 5
local SWITCH_STATE_FINISHED = 12

local CLIMB_TIMEOUT = 15000
local DESCENT_TIMEOUT = 30000
local COLLISION_TIMEOUT = 5000
local START_TOLERANCE = 5.0
local ARRIVAL_TOLERANCE = 1.0

local isTransitioning = false
local isClimbing = false
local skyReachedAt = nil
local frozenEntity = nil
local wasInvincible = false
local spinnerOn = false
local hiddenHuds = {}

local SkySwoopDown

local function genericHud(resource)
    return function(visible)
        if visible then exports[resource]:Show() else exports[resource]:Hide() end
    end
end

local function findHuds()
    local hud = Config.Hud
    local found = {}
    if not hud then return found end

    if hud ~= 'auto' then
        if GetResourceState(hud) == 'started' then
            found[hud] = Huds[hud] or genericHud(hud)
        end
        return found
    end

    for resource, toggle in pairs(Huds) do
        if GetResourceState(resource) == 'started' then
            found[resource] = toggle
        end
    end
    return found
end

local function setHud(visible)
    if visible then
        for _, toggle in pairs(hiddenHuds) do pcall(toggle, true) end
        hiddenHuds = {}
        return
    end

    hiddenHuds = findHuds()
    for _, toggle in pairs(hiddenHuds) do pcall(toggle, false) end
end

local function setSpinner(state)
    if state and Config.Spinner then
        BeginTextCommandBusyspinnerOn('STRING')
        AddTextComponentSubstringPlayerName(Config.Spinner)
        EndTextCommandBusyspinnerOn(4)
        spinnerOn = true
    elseif not state and spinnerOn then
        BusyspinnerOff()
        spinnerOn = false
    end
end

local function unfreeze()
    if frozenEntity and DoesEntityExist(frozenEntity) then
        FreezeEntityPosition(frozenEntity, false)
    end
    frozenEntity = nil
end

local function readCoords(coords)
    local kind = type(coords)
    local heading

    if kind == 'vector4' then
        heading = coords.w
    elseif kind == 'table' then
        if not (tonumber(coords.x) and tonumber(coords.y) and tonumber(coords.z)) then return end
        heading = tonumber(coords.w or coords.heading)
    elseif kind ~= 'vector3' then
        return
    end

    return vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0), heading
end

local function lockPlayer()
    local player = PlayerId()
    wasInvincible = GetPlayerInvincible(player)
    SetPlayerInvincible(player, true)
    setHud(false)

    CreateThread(function()
        while isTransitioning do
            HideHudAndRadarThisFrame()
            DisableAllControlActions(0)

            if skyReachedAt and GetGameTimer() - skyReachedAt > Config.MaxHoldTime then
                CreateThread(SkySwoopDown)
            end

            Wait(0)
        end
    end)
end

local function releasePlayer()
    unfreeze()
    setSpinner(false)
    SetPlayerInvincible(PlayerId(), wasInvincible)
    setHud(true)
    skyReachedAt = nil
    isClimbing = false
    isTransitioning = false
end

local function movePlayer(pos, heading, tolerance)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local entity = ped
    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
        entity = vehicle
    end

    if #(GetEntityCoords(entity) - pos) < tolerance then
        if heading then SetEntityHeading(entity, heading + 0.0) end
        return
    end

    unfreeze()
    FreezeEntityPosition(entity, true)
    frozenEntity = entity
    RequestCollisionAtCoord(pos.x, pos.y, pos.z)

    if entity == vehicle then
        SetPedCoordsKeepVehicle(ped, pos.x, pos.y, pos.z)
    else
        SetEntityCoords(ped, pos.x, pos.y, pos.z, false, false, false, false)
    end
    if heading then SetEntityHeading(entity, heading + 0.0) end

    local deadline = GetGameTimer() + COLLISION_TIMEOUT
    while not HasCollisionLoadedAroundEntity(entity) do
        if GetGameTimer() > deadline then return end
        RequestCollisionAtCoord(pos.x, pos.y, pos.z)
        Wait(0)
    end

    unfreeze()
    if entity == vehicle then SetVehicleOnGroundProperly(vehicle) end
end

local function climb()
    if not IsPlayerSwitchInProgress() then
        SwitchOutPlayer(PlayerPedId(), 0, SWITCH_TYPE_LONG)
    end

    local deadline = GetGameTimer() + CLIMB_TIMEOUT
    while GetPlayerSwitchState() ~= SWITCH_STATE_IN_SKY do
        Wait(0)
        if not IsPlayerSwitchInProgress() or GetGameTimer() > deadline then
            StopPlayerSwitch()
            return false
        end
    end

    return true
end

local function descend()
    if not IsPlayerSwitchInProgress() then return end
    SwitchInPlayer(PlayerPedId())

    local deadline = GetGameTimer() + DESCENT_TIMEOUT
    while IsPlayerSwitchInProgress() and GetPlayerSwitchState() ~= SWITCH_STATE_FINISHED do
        if GetGameTimer() > deadline then
            StopPlayerSwitch()
            return
        end
        Wait(0)
    end
end

local function SkySwoopUp(coords)
    if isTransitioning then return false end
    isTransitioning = true
    isClimbing = true
    lockPlayer()

    local pos, heading = readCoords(coords)
    if pos then movePlayer(pos, heading, START_TOLERANCE) end

    if not climb() then
        releasePlayer()
        return false
    end

    skyReachedAt = GetGameTimer()
    isClimbing = false
    setSpinner(true)
    return true
end

SkySwoopDown = function(coords, hold)
    while isClimbing do Wait(0) end

    local pos, heading = readCoords(coords)
    local reachedAt = skyReachedAt

    if not reachedAt then
        if pos and not isTransitioning then
            movePlayer(pos, heading, ARRIVAL_TOLERANCE)
            unfreeze()
        end
        return false
    end

    skyReachedAt = nil
    if pos then movePlayer(pos, heading, ARRIVAL_TOLERANCE) end

    local holdUntil = reachedAt + (tonumber(hold) or 0)
    while GetGameTimer() < holdUntil do Wait(0) end

    setSpinner(false)
    descend()
    releasePlayer()
    return true
end

local function transition(from, to, hold)
    if isTransitioning then return false end

    SkySwoopUp(from)
    return SkySwoopDown(to, tonumber(hold) or Config.HoldTime)
end

local function Teleport(coords, hold)
    return transition(nil, coords, hold)
end

local function TriggerCloudLoadingScreen(startCoords, endCoords, duration)
    if readCoords(endCoords) then
        return transition(startCoords, endCoords, duration)
    end
    return transition(nil, startCoords, duration)
end

local function IsActive()
    return isTransitioning
end

exports('Teleport', Teleport)
exports('TriggerCloudLoadingScreen', TriggerCloudLoadingScreen)
exports('SkySwoopUp', SkySwoopUp)
exports('SkySwoopDown', SkySwoopDown)
exports('IsActive', IsActive)

RegisterNetEvent('cloudsLoading:teleport', function(coords, hold)
    Teleport(coords, hold)
end)

RegisterNetEvent('cloudsLoading:trigger', function(startCoords, endCoords, duration)
    TriggerCloudLoadingScreen(startCoords, endCoords, duration)
end)

RegisterNetEvent('cloudsLoading:up', function(coords)
    SkySwoopUp(coords)
end)

RegisterNetEvent('cloudsLoading:down', function(coords, hold)
    SkySwoopDown(coords, hold)
end)

if Config.TestCommand then
    RegisterCommand('testclouds', function(_, args)
        local n = {}
        for i = 1, 7 do n[i] = tonumber(args[i]) end

        if n[1] and n[2] and n[3] and n[4] and n[5] and n[6] then
            TriggerCloudLoadingScreen(vector3(n[1], n[2], n[3]), vector3(n[4], n[5], n[6]), n[7])
        elseif n[1] and n[2] and n[3] then
            Teleport(vector3(n[1], n[2], n[3]), n[4])
        else
            Teleport(nil, n[1])
        end
    end, false)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() or not isTransitioning then return end
    if IsPlayerSwitchInProgress() then StopPlayerSwitch() end
    releasePlayer()
end)
