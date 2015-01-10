local concommand_name
if SERVER then
	concommand_name = "find_conflicts_hook_sv"
	util.AddNetworkString("find_conflicts_hook")
else
	concommand_name = "find_conflicts_hook_cl"
end

local SendToSuperAdmins

local ServerColor = Color(255, 128, 192)
local ResultColor
if SERVER then
	ResultColor = ServerColor
else
	ResultColor = Color(255, 192, 0)
end
if CLIENT then
	net.Receive("find_conflicts_hook", function ()
		MsgC(ServerColor, net.ReadString())
	end)
end
local function ReportHookResult (EventName, HookName, HookFunction, ...)
	local Returned = {...}
	if #Returned == 0 or (#Returned == 1 and Returned[1] == nil) then -- unverified condition
		return ...
	end
	-- Process HookName:
	if HookName != nil then
		if isstring(HookName) then
			HookName = 'hook "'..HookName..'"'
		else
			HookName = 'hook '..tostring(HookName)
		end
	else
		HookName = "GAMEMODE"
	end
	-- Process info:
	local info = debug.getinfo(HookFunction, 'S')
	-- Process list_rarg:
	local list_rarg = ""
	for k,rarg in ipairs(Returned) do
		if isstring(rarg) then
			list_rarg = list_rarg.."\n\tArg #"..tostring(k)..' = "'..rarg..'"'
		else
			list_rarg = list_rarg.."\n\tArg #"..tostring(k)..' = '..tostring(rarg)
		end
	end
	-- Finish operation:
	local resultstr = 'Event "'..EventName..'", '..HookName..',\n in "'..tostring(info.short_src)..'" (lines '..tostring(info.linedefined)..' to '..tostring(info.lastlinedefined)..'), returned:'..list_rarg..'\n\n'
	if CLIENT or !SendToSuperAdmins then
		MsgC(ResultColor, resultstr)
	else
		local superadmins = {}
		for _,ply in pairs(player.GetAll()) do
			if ply:IsSuperAdmin() then
				superadmins[#superadmins+1] = ply
			end
		end
		if #superadmins > 0 then
			net.Start("find_conflicts_hook")
				net.WriteString(resultstr)
			net.Send(superadmins)
		else
			RunConsoleCommand("find_conflicts_hook_sv", EventName, "0") -- Stop sending to superadmins if none connected.
		end
	end
	return ...
end

local function NiceMsgN (ply, ...)
	if SERVER and IsValid(ply) then
		ply:PrintMessage(HUD_PRINTCONSOLE, string.Implode("", {...}))
	else
		MsgN(...)
	end
end

local helpstr = concommand_name.." <EventName> <0|1>\n   Displays the hook result of the specified event name in order to find a hook conflict.\n"
local CancelTests = {}
concommand.Add(concommand_name, function (ply, cmd, args, fullstring)
	if CLIENT or !IsValid(ply) or ply:IsSuperAdmin() then
		local EventName = args[1]
		if !isstring(EventName) then
			NiceMsgN(ply, " - "..helpstr)
			return
		end
		local start_op = tobool(tonumber(args[2] or 1))
		local IsRunning = istable(CancelTests[EventName])
		local HookTable = hook.GetTable() -- This is a copy!
		local EventFunctions = HookTable[EventName]
		local CancelTest
		if start_op then -- begin operation
			if !IsRunning then
				if IsValid(ply) then
					SendToSuperAdmins = true
				else
					SendToSuperAdmins = false
				end
				if istable(EventFunctions) and table.Count(EventFunctions) > 0 then
					CancelTests[EventName] = {}
					CancelTest = CancelTests[EventName]
					for HookName,HookFunction in pairs(EventFunctions) do
						if isfunction(HookFunction) then
							local function new_HookFunction (...)
								return ReportHookResult(EventName, HookName, HookFunction, HookFunction(...))
							end
							CancelTest[HookName] = HookFunction
							-- hook.Remove(EventName, HookName)
							hook.Add(EventName, HookName, new_HookFunction)
						end
					end
					NiceMsgN(ply, 'Conflict test started for event name "'..EventName..'"!')
				else
					ErrorNoHalt('Could find no hook with event name "'..EventName..'"!')
					return
				end
				if isfunction(GAMEMODE[EventName]) then
					local HookFunction = GAMEMODE[EventName]
					local function new_HookFunction (...)
						return ReportHookResult(EventName, nil, HookFunction, HookFunction(...))
					end
					CancelTest[GAMEMODE] = HookFunction -- to be restored first
					GAMEMODE[EventName] = new_HookFunction
				end
			else
				NiceMsgN(ply, 'Conflict test is already started for event name "'..EventName..'"!')
			end
		else -- finish operation
			if IsRunning then
				local CancelTest = CancelTests[EventName]
				if CancelTest[GAMEMODE] != nil then
					GAMEMODE[EventName] = CancelTest[GAMEMODE]
					CancelTest[GAMEMODE] = nil
				end
				for HookName,HookFunction in pairs(EventFunctions) do -- Check the current hooks instead of the cancel list in case of removed hooks while the test was running.
					if CancelTest[HookName] != nil then
						-- hook.Remove(EventName, HookName)
						hook.Add(EventName, HookName, CancelTest[HookName])
					end
				end
				CancelTests[EventName] = nil
				NiceMsgN(ply, 'Conflict test is now stopped for event name "'..EventName..'"!')
			else
				NiceMsgN(ply, 'Conflict test is not running for event name "'..EventName..'"!')
			end
		end
	end
end, nil, helpstr, 0)
