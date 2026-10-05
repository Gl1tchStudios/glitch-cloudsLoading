local function Teleport(playerId, coords, hold)
    TriggerClientEvent('cloudsLoading:teleport', playerId, coords, hold)
end

local function TriggerCloudLoadingScreen(playerId, startCoords, endCoords, duration)
    TriggerClientEvent('cloudsLoading:trigger', playerId, startCoords, endCoords, duration)
end

local function SkySwoopUp(playerId, coords)
    TriggerClientEvent('cloudsLoading:up', playerId, coords)
end

local function SkySwoopDown(playerId, coords, hold)
    TriggerClientEvent('cloudsLoading:down', playerId, coords, hold)
end

exports('Teleport', Teleport)
exports('TriggerCloudLoadingScreen', TriggerCloudLoadingScreen)
exports('SkySwoopUp', SkySwoopUp)
exports('SkySwoopDown', SkySwoopDown)
