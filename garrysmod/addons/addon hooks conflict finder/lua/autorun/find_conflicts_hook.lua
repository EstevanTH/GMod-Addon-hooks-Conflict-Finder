if !addon_hooks_conflict_finder then
	addon_hooks_conflict_finder = {}
end

local concommand_name
if SERVER then
	concommand_name = "find_conflicts_hook_sv"
	util.AddNetworkString( "find_conflicts_hook" )
else
	concommand_name = "find_conflicts_hook_cl"
end

local SendToSuperAdmins -- parameter set below

local AddonsList -- Workshop addons list, only set when the 1st test starts
-- local PathsList -- gamemodes, root and legacy addons list, only set when the 1st test starts
local function FillAddonsList()
	AddonsList = {}
	local title
	for _,addon_info in pairs( engine.GetAddons() ) do
		title = addon_info.title
		if isstring( title ) then
			local _,folders = file.Find( "*", title )
			for _,folder in ipairs( folders ) do
				if string.lower( folder ) == "lua" then -- only listed if contains Lua
					table.insert( AddonsList, title )
					break
				end
			end
		end
	end
end

local KnownLuaFiles = {} -- cache for Lua file readable locations (table of paths or path+addon name)
local function LocateLuaFile( LuaFile )
	-- WorkshopAddons must be nil when LuaFile is not contained in any Workshop addon, otherwise it must be a table of addon names.
	--[[
	Cela ne fonctionne pas pour les addons client installés.
	Est-ce que ça fonctionne côté serveur, local ?
	Est-ce que ça fonctionne côté serveur, distant ?
	Est-ce que ça fonctionne pour les addons Workshop serveur ?
	Faut-il utiliser file.Find() au lieu de file.Exists() ?
	Est-ce que FillAddonsList() fonctionne côté client et côté serveur ?
	]]
	if !KnownLuaFiles[LuaFile] then
		local WorkshopAddons
		local f
		for _,title in ipairs( AddonsList ) do
			-- Unfortunately file.Exists() does not work with Workshop addon titles as a directory.
			f = file.Find( LuaFile, title ) -- BEWARE OF CASE-SENSITIVE file systems
			if f and #f>=1 then
				if !WorkshopAddons then
					WorkshopAddons = {}
				end
				table.insert( WorkshopAddons, title )
			end
		end
		KnownLuaFiles[LuaFile] = { -- This table can be completed if needed (legacy addons, gamemodes).
			WorkshopAddons = WorkshopAddons,
		}
	end
	return ( KnownLuaFiles[LuaFile] ).WorkshopAddons
end

local ServerColor = Color( 255, 128, 192 )
local ResultColor
if SERVER then
	ResultColor = ServerColor
else
	ResultColor = Color( 255, 192, 0 )
end
if CLIENT then
	net.Receive( "find_conflicts_hook", function()
		MsgC( ServerColor, net.ReadString() )
	end )
end
local find_conflicts_hook -- function defined below
local function ReportHookResult( EventName, HookName, HookFunction, ... )
	local Returned = { ... }
	if #Returned == 0 or ( #Returned == 1 and Returned[1] == nil ) then -- unverified condition
		return ...
	end
	-- Process HookName:
	if HookName != nil then
		if isstring( HookName ) then
			HookName = 'hook "'..HookName..'"'
		else
			HookName = 'hook '..tostring( HookName )
		end
	else
		HookName = "GAMEMODE"
	end
	-- Process info:
	local info = debug.getinfo( HookFunction, 'S' )
	-- MsgN( "info" ); PrintTable( info ) -- debug
	-- Process list_rarg:
	local list_rarg = ""
	for k,rarg in ipairs( Returned ) do
		if isstring( rarg ) then
			list_rarg = list_rarg.."\n\tArg #"..tostring( k )..' = "'..rarg..'"'
		else
			list_rarg = list_rarg.."\n\tArg #"..tostring( k )..' = '..tostring( rarg )
		end
	end
	-- Finish operation:
	local LuaFile = tostring( info.short_src )
	local foundstr
	do
		local locations = LocateLuaFile( LuaFile )
		if !locations then
			foundstr = "not found in Workshop addons"
		elseif #locations == 1 then
			foundstr = "found in Workshop addon « "..locations[1].." »"
		else
			foundstr = "found in Workshop addons « "..string.Implode( " », « ", locations ).." »"
		end
	end
	local resultstr = 'Event "'..EventName..'", '..HookName..',\n in "'..LuaFile..'" (lines '..tostring( info.linedefined )..' to '..tostring( info.lastlinedefined )..'),\n '..foundstr..', returned:'..list_rarg..'\n\n'
	if CLIENT or !SendToSuperAdmins then
		MsgC( ResultColor, resultstr )
	else
		local superadmins = {}
		for _,ply in pairs( player.GetAll() ) do
			if ply:IsSuperAdmin() then
				superadmins[#superadmins+1] = ply
			end
		end
		if #superadmins > 0 then
			net.Start( "find_conflicts_hook" )
				net.WriteString( resultstr )
			net.Send( superadmins )
		else
			find_conflicts_hook( nil, concommand_name, { EventName, 0 }, concommand_name..' "'..EventName..'" "0"' ) -- Stop sending to superadmins if none connected.
		end
	end
	return ...
end

local function NiceMsgN( ply, ... )
	if SERVER and IsValid( ply ) then
		ply:PrintMessage( HUD_PRINTCONSOLE, string.Implode( "", { ... } ) )
	else
		MsgN( ... )
	end
end

local helpstr = concommand_name.." <EventName> <0|1>\n   Displays the hook result of the specified event name in order to find a hook conflict.\n"
local CancelTests
if addon_hooks_conflict_finder.CancelTests then
	CancelTests = addon_hooks_conflict_finder.CancelTests
else
	CancelTests = {}
	addon_hooks_conflict_finder.CancelTests = CancelTests
end
function find_conflicts_hook( ply, cmd, args, fullstring )
	if CLIENT or !IsValid( ply ) or ply:IsSuperAdmin() then
		local EventName = args[1]
		if !isstring( EventName ) then
			NiceMsgN( ply, " - "..helpstr )
			return
		end
		if !AddonsList then
			FillAddonsList()
		end
		local start_op = tobool( tonumber( args[2] or 1 ) )
		local IsRunning = istable( CancelTests[EventName] )
		local HookTable = hook.GetTable() -- This is a copy!
		local EventFunctions = HookTable[EventName]
		local CancelTest
		if start_op then -- begin operation
			if !IsRunning then
				if IsValid( ply ) then
					SendToSuperAdmins = true
				else
					SendToSuperAdmins = false
				end
				if istable( EventFunctions ) and table.Count( EventFunctions ) > 0 then
					CancelTests[EventName] = {}
					CancelTest = CancelTests[EventName]
					for HookName,HookFunction in pairs( EventFunctions ) do
						if isfunction( HookFunction ) then
							local function new_HookFunction( ... )
								return ReportHookResult( EventName, HookName, HookFunction, HookFunction(...) )
							end
							CancelTest[HookName] = HookFunction
							-- hook.Remove( EventName, HookName ) -- useless
							hook.Add( EventName, HookName, new_HookFunction )
						end
					end
					NiceMsgN( ply, 'Conflict test started for event name "'..EventName..'"!' )
				else
					NiceMsgN( 'Could find no hook with event name "'..EventName..'"!' )
					return
				end
				if isfunction( GAMEMODE[EventName] ) then
					local HookFunction = GAMEMODE[EventName]
					local function new_HookFunction( ... )
						return ReportHookResult( EventName, nil, HookFunction, HookFunction( ... ) )
					end
					CancelTest[GAMEMODE] = HookFunction -- to be restored first
					GAMEMODE[EventName] = new_HookFunction
				end
			else
				NiceMsgN( ply, 'Conflict test is already started for event name "'..EventName..'"!' )
			end
		else -- finish operation
			if IsRunning then
				local CancelTest = CancelTests[EventName]
				if CancelTest[GAMEMODE] != nil then
					GAMEMODE[EventName] = CancelTest[GAMEMODE]
					CancelTest[GAMEMODE] = nil
				end
				for HookName,HookFunction in pairs( EventFunctions ) do -- Check the current hooks instead of the cancel list in case of removed hooks while the test was running.
					if CancelTest[HookName] != nil then
						-- hook.Remove( EventName, HookName ) -- useless
						hook.Add( EventName, HookName, CancelTest[HookName] )
					end
				end
				CancelTests[EventName] = nil
				NiceMsgN( ply, 'Conflict test is now stopped for event name "'..EventName..'"!' )
			else
				NiceMsgN( ply, 'Conflict test is not running for event name "'..EventName..'"!' )
			end
		end
	end
end
concommand.Add( concommand_name, find_conflicts_hook, nil, helpstr, 0 )
