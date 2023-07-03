local skynet = require "skynet.manager"

local loadfile = loadfile
local assert = assert
local ipairs = ipairs
local pairs = pairs
local os = os
local tinsert = table.insert
local tremove = table.remove
local tunpack = table.unpack
local skynet_send = skynet.send
local skynet_call = skynet.call
local skynet_pack = skynet.pack
local skynet_ret = skynet.ret

local NORET = {}

local g_module_id_list_map = {}
local g_module_watch_map = {}
local g_module_version_map = {}

local CMD = {}

local function before_exit_module(module_name)
	local old_id_list = g_module_id_list_map[module_name] or {}
	for _,id in ipairs(old_id_list) do
		skynet_send(id,'lua','before_exit')
	end
end

local function exit_module(module_name)
	local old_id_list = g_module_id_list_map[module_name] or {}
	for _,id in ipairs(old_id_list) do
		skynet_send(id,'lua','exit')
	end
end

function CMD.kill_module(source,module_name)
	assert(module_name,'not module_name')
	before_exit_module(module_name)
	exit_module(module_name)
	
	g_module_id_list_map[module_name] = nil
	g_module_watch_map[module_name] = nil
	g_module_version_map[module_name] = nil
end

function CMD.kill_all(source)
	for module_name,_ in pairs(g_module_id_list_map) do
		CMD.kill_module(source,module_name)
	end
end

function CMD.load_module(source,module_name)
	assert(module_name,'not module_name')
	local mod_args = {}
	local default_arg = {}
	
	local mod_config = loadfile("mod_config.lua")()
	assert(mod_config,"not mod_config")
	local m_cfg = mod_config[module_name]
	assert(m_cfg,"not m_cfg")
	local launch_num = m_cfg.launch_num
	local mod_args = m_cfg.mod_args or {}
	local default_arg = m_cfg.default_arg or {}

	before_exit_module(module_name)

	local id_list = {}
	for i = 1,launch_num do		
		local server_id = skynet.newservice('hot_container',module_name,i,os.date("%Y-%m-%d %H:%M:%S",os.time()))
		skynet_call(server_id,'lua','start',mod_args[i] or default_arg)
		tinsert(id_list,server_id)
	end

	exit_module(module_name)

	g_module_id_list_map[module_name] = id_list

	if not g_module_version_map[module_name] then
		g_module_version_map[module_name] = 0
	end

	if not g_module_watch_map[module_name] then
		g_module_watch_map[module_name] = {}
	end
	
	g_module_version_map[module_name] = g_module_version_map[module_name] + 1
	local version = g_module_version_map[module_name]

	local watch_map = g_module_watch_map[module_name]
	for source,response in pairs(watch_map) do
		response(true,id_list,version)
		watch_map[source] = nil
	end
	
	return id_list,version
end

function CMD.query(source,module_name)
	assert(module_name,'not module_name')
	assert(g_module_id_list_map[module_name])
	assert(g_module_version_map[module_name])

	local id_list = g_module_id_list_map[module_name]
	local version = g_module_version_map[module_name]

	return id_list,version
end

function CMD.watch(source,module_name,version)
    assert(module_name,'not module_name')
	assert(version,"not version")
	assert(g_module_id_list_map[module_name])
	assert(g_module_version_map[module_name])

	local id_list = g_module_id_list_map[module_name]
	local version = g_module_version_map[module_name]
	local watch_map = g_module_watch_map[module_name]

	assert(not watch_map[source])
	if version ~= version then
		return id_list,version
	end

	watch_map[source] = skynet.response()
	return NORET
end

function CMD.unwatch(source,module_name)
	assert(module_name,'not module_name')
	assert(g_module_id_list_map[module_name])
	assert(g_module_version_map[module_name])

	local id_list = g_module_id_list_map[module_name]
	local version = g_module_version_map[module_name]
	local watch_map = g_module_watch_map[module_name]
	local response = watch_map[source]
	assert(response)

	response(true,id_list,version)
	watch_map[source] = nil
	return true
end

skynet.start(function()
	skynet.register('.contriner_mgr')
	skynet.dispatch('lua',function(session,source,cmd,...)
		local f = CMD[cmd]
		assert(f,'cmd no found :'..cmd)
		local r1,r2 = f(source,...)
		if r1 ~= NORET then
			skynet_ret(skynet_pack(r1,r2))
		end
	end)
end)