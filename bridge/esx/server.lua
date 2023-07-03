if UseOx or GetResourceState("es_extended") ~= "started" then return end

ESX = not UseOx and exports.es_extended.getSharedObject() --[[@as table | false]]

if not ESX then return end

---@param source integer
---@return table
function GetPlayerFromId(source)
	return ESX.GetPlayerFromId(source)
end

---@param identifier string
---@return table
function GetPlayerFromIdentifier(identifier)
	return ESX.GetPlayerFromIdentifier(identifier)
end

---@param player table
---@return string
function GetIdentifier(player)
	return player.identifier
end

---@param source integer
---@return number
function GetMoney(source)
	local player = GetPlayerFromId(source)
	if not player then return 0 end

	return player.getMoney()
end

---@param source integer
---@param amount number
function RemoveMoney(source, amount)
	local player = GetPlayerFromId(source)
	if not player then return end

	player.removeMoney(amount)
end