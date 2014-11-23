util.AddNetworkString("DL_SlayMessage")
util.AddNetworkString("DL_AutoSlay")

hook.Add("PlayerAuthed", "DamagelogNames", function(ply, steamid, uniqueid)
	if Damagelog.Use_MySQL and Damagelog.MySQL_Connected then
		local query_str = "SELECT slays FROM damagelog_autoslay WHERE steamid = '"..steamid.."' LIMIT 1;"
		local query = Damagelog.database:query(query_str)
		query.onSuccess = function(self)
			if not IsValid(ply) then return end
			local data = self:getData()
			ply:SetNWInt("Autoslays_left", data or 0)
		end
		query:start()
	end	
end)

function Damagelog.SlayMessage(ply, message)
	net.Start("DL_SlayMessage")
	net.WriteString(message)
	net.Send(ply)
end

function Damagelog:CreateSlayList(tbl)
	if #tbl == 1 then
		return self:GetName(tbl[1])
	else
		local result = ""
		for i=1, #tbl do
			if i == #tbl then 
				result = result.." and "..self:GetName(tbl[i]) 
			elseif i == 1 then 
				result = self:GetName(tbl[i]) 
			else 
				result = result..", "..self:GetName(tbl[i])
			end
		end
		return result
	end
end

-- ty evolve
function Damagelog:FormatTime(t)
	if t < 0 then
		return "Forever"
	elseif t < 60 then
		if t == 1 then return "one second" else return t.." seconds" end
	elseif t < 3600 then
		if math.ceil(t/60) == 1 then return "one minute" else return math.ceil(t/60).." minutes" end
	elseif t < 24*3600 then
		if math.ceil(t/3600) == 1 then return "one hour" else return math.ceil(t/3600).." hours" end
	elseif t < 24*3600* 7 then
		if math.ceil(t/(24*3600)) == 1 then return "one day" else return math.ceil(t/(24*3600)).." days" end
	elseif t < 24*3600*30 then
		if math.ceil(t/(24*3600*7)) == 1 then return "one week" else return math.ceil(t/(24*3600*7)).." weeks" end
	else
		if math.ceil(t/(24*3600*30)) == 1 then return "one month" else return math.ceil(t/(24*3600*30)).." months" end
	end
end

local function NetworkSlays(steamid, number)
	for k,v in pairs(player.GetAll()) do
		if v:SteamID() == steamid then
			v:SetNWInt("Autoslays_left", number)
			return
		end
	end
end

function Damagelog:SetSlays(admin, steamid, slays, reason, target)
	if Damagelog.Use_MySQL and Damagelog.MySQL_Connected then
		if reason == "" then
			reason = "No reason specified"
		end
		if slays == 0 then
			local query_str = "DELETE FROM damagelog_autoslay WHERE steamid = '"..steamid.."';"
			local query = Damagelog.database:query(query_str)
			query:start()
			local name = self:GetName(steamid)
			ulx.fancyLogAdmin(admin, "#A removed the autoslays of #T.", target)
			NetworkSlays(steamid, 0)
		else
		    local query_str = "SELECT * FROM damagelog_autoslay WHERE steamid = '"..steamid.."' LIMIT 1;"
			local query = Damagelog.database:query(query_str)
			query.onSuccess = function(self)
				if not IsValid(ply) then return end
				local data = self:getData()
				if data then
					local adminid
					if IsValid(admin) and type(admin) == "Player" then
						adminid = admin:SteamID()
					else
						adminid = "Console"
					end
					local old_slays = tonumber(data.slays)
					local old_steamids = util.JSONToTable(data.admins) or {}
				    local new_steamids = table.Copy(old_steamids)
			        if not table.HasValue(new_steamids, adminid) then
					    table.insert(new_steamids, adminid)
					end
				    if old_slays == slays then
				    	local query_str = "UPDATE damagelog_autoslay SET admins = "..sql.SQLStr(util.TableToJSON(new_steamids))..", reason = "..sql.SQLStr(reason)..", time = "..os.time().." WHERE steamid = '"..steamid.."' LIMIT 1;"
						local localquery = Damagelog.database:query(query_str)
						localquery:start()
						local list = self:CreateSlayList(new_steamids)
						local nick = self:GetName(steamid)
						ulx.fancyLogAdmin(admin, "#A changed the reason of #T's autoslay to : '#s'. He was already autoslain "..slays.." time(s) by #s.", target, reason, list)
					else
						local difference = slays - old_slays
						local query_str = string.format("UPDATE damagelog_autoslay SET admins = %s, slays = %i, reason = %s, time = %s WHERE steamid = '%s' LIMIT 1;", sql.SQLStr(new_admins), slays, sql.SQLStr(reason), tostring(os.time()), steamid)
						local localquery = Damagelog.database:query(query_str)
						localquery:start()
						local list = self:CreateSlayList(new_steamids)
						local nick = self:GetName(steamid)
						ulx.fancyLogAdmin(admin, "#A "..(difference > 0 and "added " or "removed ")..math.abs(difference).." slays to #T for the reason : '#s'. He was previously autoslain "..old_slays.." time(s) by #s.", target, reason, list)
						NetworkSlays(steamid, slays)
					end
				else
					local admins
					if IsValid(admin) and type(admin) == "Player" then
					    admins = util.TableToJSON( { admin:SteamID() } )
					else
					    admins = util.TableToJSON( { "Console" } )
					end
					local query_str = string.format("INSERT INTO damagelog_autoslay (`admins`, `steamid`, `slays`, `reason`, `time`) VALUES (%s, '%s', %i, %s, %s)", sql.SQLStr(admins), steamid, slays, sql.SQLStr(reason), tostring(os.time()))
					local localquery = Damagelog.database:query(query_str)
					localquery:start()
					ulx.fancyLogAdmin(admin, "#A added "..slays.." autoslays to #T with the reason : '#s'", target, reason)
					NetworkSlays(steamid, slays)
				end
			end
			query:start()
		end
	else
		print("Fu MySQL")
	end
end

hook.Add("TTTBeginRound", "Damagelog_AutoSlay", function()
	for k,v in pairs(player.GetAll()) do
		if v:IsActive() then
			timer.Simple(1, function()
				v:SetNWBool("PlayedSRound", true)
			end)

			local query_str = "SELECT * FROM damagelog_autoslay WHERE steamid = '"..v:SteamID().."' LIMIT 1;"
			local query = Damagelog.database:query(query_str)
			query.onSuccess = function(self)
				if data then
					v:Kill()
					local admins = util.JSONToTable(data.admins) or {}
					local slays = data.slays
					local reason = data.reason
					local _time = data.time
					slays = slays - 1
					if slays <= 0 then
						local query_str = "DELETE FROM damagelog_autoslay WHERE steamid = '"..v:SteamID().."';"
						local localquery = Damagelog.database:query(query_str)
						localquery:start()
						NetworkSlays(steamid, 0)
					else
						local query_str = "UPDATE damagelog_autoslay SET slays = slays - 1 WHERE steamid = '"..v:SteamID().."';"
						local localquery = Damagelog.database:query(query_str)
						localquery:start()
						NetworkSlays(steamid, slays - 1)
					end
					local list = Damagelog:CreateSlayList(admins)
					net.Start("DL_AutoSlay")
					net.WriteEntity(v)
					net.WriteString(list)
					net.WriteString(reason)
					net.WriteString(Damagelog:FormatTime(tonumber(os.time()) - tonumber(_time)))
					net.Broadcast()
					if IsValid(v.server_ragdoll) then
						local ply = player.GetByUniqueID(v.server_ragdoll.uqid)
						ply:SetCleanRound(false)
						ply:SetNWBool("body_found", true)
						CORPSE.SetFound(v.server_ragdoll, true)
						v.server_ragdoll:Remove()
					end
				end
			end
			query:start()
		end
	end	
end)
