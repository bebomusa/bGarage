if CheckVersion then
	lib.versionCheck("bebomusa/vgarage")
end

--#region Variables

---@type table <string, Vehicle>
local vehicles = {}
---@type table <string | number, vector4>
local parkingSpots = {}
local hasStarted = false

--#endregion Variables

--#region Functions

---Add a vehicle
---@param owner string | number The identifier of the owner of the car, 'charid' for Ox, 'identifier' for ESX
---@param plate string The plate number of the car
---@param model string | number The hash of the model
---@param props? table The vehicle properties
---@param location? 'outside' | 'parked' | 'impound' The location that the vehicle is at
---@param _type? string Type of the vehicle
---@param temporary? boolean If true, will not add the vehicle to the database
---@return boolean
local function addVehicle(owner, plate, model, props, location, _type, temporary)
	plate = plate and plate:upper() or plate
	if not owner or not plate or not model then return false end
	if vehicles[plate] then return true end

	model = type(model) == "string" and joaat(model) or model
	props = props or {}
	location = location or "outside"

	vehicles[plate] = {
		owner = owner,
		model = model,
		props = props,
		location = location,
		type = _type,
		temporary = temporary,
	}

	return true
end

exports("addVehicle", addVehicle)

---Remove a vehicle
---@param plate string The plate number of the car
---@return boolean
local function removeVehicle(plate)
	plate = plate and plate:upper() or plate
	if not plate or not vehicles[plate] then return false end

	vehicles[plate] = nil

	return true
end

exports("removeVehicle", removeVehicle)

---Get a vehicle by its plate
---@param plate string The plate number of the car
---@return Vehicle?
local function getVehicle(plate)
	plate = plate and plate:upper() or plate
	return vehicles[plate]
end

exports("getVehicle", getVehicle)

---Get a vehicle by its plate and check if they're owner
---@param source integer
---@param plate string The plate number of the car
---@return Vehicle?
local function getVehicleOwner(source, plate)
	local ply = GetPlayerFromId(source)
	local owner = GetIdentifier(ply)
	local vehData = getVehicle(plate)
	local isOwner = vehData and vehData.owner == owner
	return isOwner and vehData or nil
end

exports("getVehicleOwner", getVehicleOwner)

---Get all vehicles from an owner, with an optional location filter
---@param owner string | number The identifier of the owner of the car, 'charid' for Ox, 'identifier' for ESX
---@param location? 'outside' | 'parked' | 'impound' The location that the vehicle is at
---@return table<string, Vehicle>, number
local function getVehicles(owner, location)
	local ownedVehicles = {}
	local amount = 0
	for k, v in pairs(vehicles) do
		if v.owner == owner and (location and v.location == location or not location) then
			ownedVehicles[k] = v
			amount += 1
		end
	end

	return ownedVehicles, amount
end

exports("getVehicles", getVehicles)

---Set the status of a vehicle and perform actions based on it, doesn't work with the 'outside' status
---@param owner string | number The identifier of the owner of the car, 'charid' for Ox, 'identifier' for ESX
---@param plate string The plate number of the car
---@param status 'parked' | 'impound' The location that the vehicle is at, so the status
---@param props? table The vehicle properties
---@return boolean
---@return string
local function setVehicleStatus(owner, plate, status, props)
	plate = plate and plate:upper() or plate

	if not owner or not vehicles[plate] or not plate then return false, locale("failed_to_set_status") end

	local ply = GetPlayerFromIdentifier(owner)
	if not ply or vehicles[plate].owner ~= owner then return false, locale("not_owner") end

	if status == "parked" and ParkingPrice ~= -1 then
		if GetMoney(ply.source) < ParkingPrice then return false, locale("invalid_funds") end
		RemoveMoney(ply.source, ParkingPrice)
	end

	vehicles[plate].location = status
	vehicles[plate].props = props or {}

	return true, status == "parked" and locale("successfully_parked") or status == "impound" and locale("successfully_impounded") or ""
end

exports("setVehicleStatus", setVehicleStatus)

---source https://github.com/Qbox-project/qbx-core/blob/main/modules/utils.lua#L106
local stringCharset = {}
local numberCharset = {}

for i = 48, 57 do numberCharset[#numberCharset + 1] = string.char(i) end
for i = 65, 90 do stringCharset[#stringCharset + 1] = string.char(i) end

local globalCharset = {}

for i = 1, #stringCharset do globalCharset[#globalCharset + 1] = stringCharset[i] end
for i = 1, #numberCharset do globalCharset[#globalCharset + 1] = numberCharset[i] end

---Shuffle table for more randomization
for i = #globalCharset, 2, -1 do
	local j = math.random(i)
	globalCharset[i], globalCharset[j] = globalCharset[j], globalCharset[i]
end

---@return string
local function getRandomLetter(length)
	if length <= 0 then return "" end
	return getRandomLetter(length - 1) .. stringCharset[math.random(1, #stringCharset)]
end

---@return string
local function getRandomNumber(length)
	if length <= 0 then return "" end
	return getRandomNumber(length - 1) .. numberCharset[math.random(1, #numberCharset)]
end

---@return string
local function getRandomAny(length)
	if length <= 0 then return "" end
	return getRandomAny(length - 1) .. globalCharset[math.random(1, #globalCharset)]
end

---@return string
local function getRandomPlate()
	local pattern = PlateTextPattern
	local newPattern = ""
	local skipNext = false
	for i = 1, #pattern do
		if not skipNext then
			local last = i == #pattern
			local c = pattern:sub(i, i)
			local nextC = last and "\0" or pattern:sub(i + 1, i + 1)
			local curC = ""

			if c == "1" then
				curC = getRandomNumber(1)
			elseif c == "A" then
				curC = getRandomLetter(1)
			elseif c == "." then
				curC = getRandomAny(1)
			elseif c == "^" and (nextC == "1" or nextC == "A" or nextC == ".") then
				curC = nextC
				skipNext = true
			else
				curC = c
			end

			newPattern = newPattern .. curC
		else
			skipNext = false
		end
	end

	return newPattern:upper()
end

exports("getRandomPlate", getRandomPlate)

---Save all vehicles to the database
local function save()
	local queries = {}

	for k, v in pairs(vehicles) do
		if not v.temporary then
			queries[#queries + 1] = {
				query = "INSERT INTO `vgarage_vehicles` (`owner`, `plate`, `model`, `props`, `location`, `type`) VALUES (:owner, :plate, :model, :props, :location, :type) ON DUPLICATE KEY UPDATE props = :props, location = :location",
				values = {
					owner = tostring(v.owner),
					plate = k,
					model = v.model,
					props = json.encode(v.props),
					location = v.location,
					type = v.type,
				},
			}
		end
	end

	for k, v in pairs(parkingSpots) do
		queries[#queries + 1] = {
			query = "INSERT INTO `vgarage_parkingspots` (`owner`, `coords`) VALUES (:owner, :coords) ON DUPLICATE KEY UPDATE coords = :coords",
			values = { owner = tostring(k), coords = json.encode(v) },
		}
	end

	if table.type(queries) == "empty" then return end

	MySQL.transaction(queries, function() end)
end

exports("save", save)

--#endregion Functions

--#region Callbacks

---@param plate string
lib.callback.register("vgarage:server:getVehicle", function(_, plate)
	return getVehicle(plate)
end)

---@param source integer
---@param plate string
lib.callback.register("vgarage:server:getVehicleOwner", function(source, plate)
	return getVehicleOwner(source, plate)
end)

---@param source integer
lib.callback.register("vgarage:server:getVehicles", function(source)
	local ply = GetPlayerFromId(source)
	local owner = GetIdentifier(ply)
	return getVehicles(owner)
end)

---@param source integer
lib.callback.register("vgarage:server:getParkedVehicles", function(source)
	local ply = GetPlayerFromId(source)
	local owner = GetIdentifier(ply)
	return getVehicles(owner, "parked")
end)

---@param source integer
lib.callback.register("vgarage:server:getImpoundedVehicles", function(source)
	local ply = GetPlayerFromId(source)
	local owner = GetIdentifier(ply)
	return getVehicles(owner, "impound")
end)

---@param plate string
lib.callback.register("vgarage:server:getOutsideVehicle", function(_, plate)
	plate = plate and plate:upper() or plate
	if not vehicles[plate] then return end

	local pool = GetAllVehicles()

	for i = 1, #pool do
		local veh = pool[i]
		if GetVehicleNumberPlateText(veh) == plate then
			return NetworkGetNetworkIdFromEntity(veh)
		end
	end
end)

---@param plate string
lib.callback.register("vgarage:server:getOutsideVehicleCoords", function(_, plate)
	plate = plate and plate:upper() or plate
	if not vehicles[plate] then return end

	local pool = GetAllVehicles()

	for i = 1, #pool do
		local veh = pool[i]
		if GetVehicleNumberPlateText(veh) == plate then
			return GetEntityCoords(veh)
		end
	end
end)

---@param source integer
lib.callback.register("vgarage:server:getOutsideVehicles", function(source)
	local ply = GetPlayerFromId(source)
	local owner = GetIdentifier(ply)
	return getVehicles(owner, "outside")
end)

---@param source integer
---@param status 'parked' | 'impound'
---@param plate string
---@param props? table
---@param owner? string | number
lib.callback.register("vgarage:server:setVehicleStatus", function(source, status, plate, props, owner)
	if not owner then
		local ply = GetPlayerFromId(source)
		if not ply then return false, locale("failed_to_set_status") end
		owner = GetIdentifier(ply)
	end
	return setVehicleStatus(owner, plate, status, props)
end)

---@param model number
---@param coords vector4
---@param plate string
lib.callback.register("vgarage:server:spawnVehicle", function(_, model, coords, plate)
	print("Spawning vehicle: model: " .. model, "plate: " .. plate)
	print("Location: " .. coords)
	plate = plate and plate:upper() or plate
	if not plate or not vehicles[plate] or not model or not coords then return end

	vehicles[plate].location = "outside"

	local tempVehicle = CreateVehicle(model, 0, 0, 0, 0, true, true)
	print("Created tempVehicle: " .. tempVehicle)

	while not DoesEntityExist(tempVehicle) do
		Wait(0)
	end

	local entityType = GetVehicleType(tempVehicle)
	DeleteEntity(tempVehicle)
	print("Got entity type: " .. entityType)

	local veh = CreateVehicleServerSetter(model, entityType, coords.x, coords.y, coords.z, coords.w)

	while not DoesEntityExist(veh) do
		Wait(0)
	end

	SetVehicleNumberPlateText(veh, plate)

	print("Spawned actual vehicle: " .. veh)
	print("Network id: " .. NetworkGetNetworkIdFromEntity(veh))
	return NetworkGetNetworkIdFromEntity(veh)
end)

---@param source integer
---@param price number
---@param takeMoney? boolean
lib.callback.register("vgarage:server:payment", function(source, price, takeMoney)
	if price == -1 then return true end
	if GetMoney(source) < price then return false, locale("invalid_funds") end
	if takeMoney then RemoveMoney(source, price) end
	return true
end)

---@param target integer
---@param model string | number
lib.callback.register("vgarage:server:giveVehicle", function(_, target, model)
	if not target or not model then return false, locale("missing_model") end

	local ply = GetPlayerFromId(target)
	if not ply then return false, locale("player_doesnt_exist") end

	local plate = getRandomPlate()
	local success = addVehicle(GetIdentifier(ply), plate, model, {}, "parked")
	return success, success and locale("successfully_add"):format(model, target) or "Failed to add the vehicle", plate
end)

---@param netId integer
lib.callback.register("vgarage:server:deleteVehicle", function(_, netId)
	if not netId or netId == 0 then return false end

	local vehicle = NetworkGetEntityFromNetworkId(netId)
	if not vehicle or vehicle == 0 then return false end

	DeleteEntity(vehicle)

	return true
end)

---@param source integer
---@param coords vector4
lib.callback.register("vgarage:server:setParkingSpot", function(source, coords)
	local ply = GetPlayerFromId(source)

	if not coords or not ply then return false, locale("failed_to_save_parking") end

	parkingSpots[GetIdentifier(ply)] = coords
	return true, locale("successfully_saved_parking")
end)

lib.callback.register("vgarage:server:getParkingSpot", function(source)
	local ply = GetPlayerFromId(source)
	if not ply then return end

	return parkingSpots[GetIdentifier(ply)]
end)

lib.callback.register("vgarage:server:hasStarted", function()
	return hasStarted
end)

lib.callback.register("vgarage:server:getRandomPlate", function()
	return getRandomPlate()
end)

--#endregion Callbacks

--#region Events

---@param plate string
---@param netId integer
RegisterNetEvent("vgarage:server:vehicleSpawnFailed", function(plate, netId)
	plate = plate and plate:upper() or plate

	if not plate or not vehicles[plate] then return end

	local ply = GetPlayerFromId(source)
	if not ply or vehicles[plate].owner ~= GetIdentifier(ply) then return end

	vehicles[plate].location = "impound"

	if not netId then return end

	local veh = NetworkGetEntityFromNetworkId(netId)
	if not veh or veh == 0 then return end

	DeleteEntity(veh)
end)

---@param resource string
AddEventHandler("onResourceStop", function(resource)
	if resource ~= GetCurrentResourceName() then return end
	save()
end)

---Onesync event that is triggered when an entity is removed from the server
---@param entity number
AddEventHandler("entityRemoved", function(entity)
	if GetEntityType(entity) ~= 2 then return end

	local plate = GetVehicleNumberPlateText(entity)

	local data = vehicles[plate]
	if not data then return end

	if data.location ~= "outside" then return end

	vehicles[plate].location = "impound"
end)

--#endregion Events

--#region Threads

CreateThread(function()
	Wait(1000)

	local success, result = pcall(MySQL.query.await, "SELECT * FROM vgarage_vehicles")

	if success then
		for i = 1, #result do
			local data = result[i] --[[@as VehicleDatabase]]
			local props = json.decode(data.props) --[[@as table]]
			vehicles[data.plate] = {
				owner = UseOx and tonumber(data.owner) --[[@as number]] or data.owner,
				model = data.model,
				props = props,
				location = data.location,
				type = data.type,
			}
		end
	else
		MySQL.query.await("CREATE TABLE vgarage_vehicles (owner VARCHAR(255) NOT NULL, plate VARCHAR(8) NOT NULL, model INT NOT NULL, props LONGTEXT NOT NULL, location VARCHAR(255) DEFAULT 'impound', type VARCHAR(255) DEFAULT 'car', PRIMARY KEY (plate))")
	end

	success, result = pcall(MySQL.query.await, "SELECT * FROM vgarage_parkingspots")

	if success then
		for i = 1, #result do
			local data = result[i]
			local owner = UseOx and tonumber(data.owner) or data.owner
			local coords = json.decode(data.coords)
			parkingSpots[owner] = vec4(coords.x, coords.y, coords.z, coords.w)
		end
	else
		MySQL.query.await("CREATE TABLE vgarage_parkingspots (owner VARCHAR(255) NOT NULL, coords LONGTEXT DEFAULT NULL, PRIMARY KEY (owner))")
	end

	hasStarted = true
	TriggerClientEvent("vgarage:client:started", -1)
end)

lib.cron.new(("*/%s * * * *"):format(TickTime), function()
    save()
end)

CreateThread(function()
	while true do
		Wait(500)

		local spawnedVehicles = {}
		local spawningVehicles = {}
		local pool = GetAllVehicles()
		local players = GetPlayers()

		for i = 1, #players do
			local player = players[i]
			local spawnedVehicle = lib.callback.await("vgarage:client:getTempVehicle", player)
			if spawnedVehicle then
				spawningVehicles[spawnedVehicle] = true
			end
		end

		for i = 1, #pool do
			if DoesEntityExist(pool[i]) then
				spawnedVehicles[GetVehicleNumberPlateText(pool[i])] = pool[i]
			end
		end

		for k, v in pairs(vehicles) do
			if v.location == "outside" and not spawnedVehicles[k] and not spawningVehicles[k] then
				vehicles[k].location = "impound"
			end
		end
	end
end)

--#endregion Threads

lib.addCommand("admincar", {
	help = locale("cmd_help"),
	restricted = AdminGroup,
	---@param source integer
}, function(source)
	if not hasStarted then return end

	local ply = GetPlayerFromId(source)
	if not ply then return end

	local ped = GetPlayerPed(source)
	local vehicle = GetVehiclePedIsIn(ped, false)

	if vehicle == 0 then
		ShowNotification(source, locale("not_in_vehicle"), "car", "error")
		return
	end

	local added = addVehicle(GetIdentifier(ply), GetVehicleNumberPlateText(vehicle), GetEntityModel(vehicle), {}, "outside", "car", false)
	ShowNotification(source, added and locale("successfully_set") or locale("failed_to_set"), "car", "success" or "error")
end)

---Do not rename this resource or touch this part of the code
local function initializeResource()
	if GetCurrentResourceName() ~= "vgarage" then
		error("^It is required to keep this resource name original, change the folder name back to 'vgarage'.^0")
		return
	end

	print("^2Resource has been initialized!^0")
end

MySQL.ready(initializeResource)