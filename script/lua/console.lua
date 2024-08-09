local ARGV = {...}
local skynet_fly_path = ARGV[1]
local svr_name = ARGV[2]
local load_modsfile = ARGV[3]
local cmd = ARGV[4]
assert(skynet_fly_path,'缺少 skynet_fly_path' .. table.concat(ARGV,','))
assert(svr_name,'缺少 svr_name' .. table.concat(ARGV, ','))
assert(load_modsfile, "缺少 启动配置文件 " .. table.concat(ARGV,','))
assert(cmd,"缺少命令 " .. table.concat(ARGV,','))

package.cpath = skynet_fly_path .. "/luaclib/?.so;"
package.path = './?.lua;' .. skynet_fly_path .."/lualib/?.lua;"

local ARGV_HEAD = 4

local lfs = require "lfs"
local file_util = require "skynet-fly.utils.file_util"
local table_util = require "skynet-fly.utils.table_util"
local time_util = require "skynet-fly.utils.time_util"
local json = require "cjson"
debug_port = nil
local skynet_cfg_path = string.format("%s_config.lua.%s.run",svr_name, load_modsfile)  --读取skynet启动配置
local file = loadfile(skynet_cfg_path)
if file then
	file()
end

local function get_host()
	assert(debug_port)
	return string.format("http://127.0.0.1:%s",debug_port)
end

local CMD = {}

function CMD.get_list()
	print(get_host() .. '/list')
end

function CMD.find_server_id()
	local module_name = assert(ARGV[ARGV_HEAD + 1])
	local offset = assert(ARGV[ARGV_HEAD + 2])
	for i = ARGV_HEAD + 3,#ARGV do
		local line = ARGV[i]
		if string.find(line,module_name,nil,true) then
			print(ARGV[i - offset])
			return
		end
	end
	assert(1 == 2)
end

function CMD.reload()
	local file = io.open(string.format("./%s.tmp_reload_cmd.txt", load_modsfile),'w+')
	assert(file)
	local load_mods = loadfile(load_modsfile)()
	local server_id = assert(ARGV[ARGV_HEAD + 1])
	local mod_name_str = ",0"
	for i = ARGV_HEAD + 2,#ARGV, 2 do
		local module_name = ARGV[i]
		mod_name_str = mod_name_str .. ',"' .. module_name .. '"'
		assert(load_mods[module_name], "module_name not exists " .. module_name)
	end
	local reload_url = string.format('%s/call/%s/"load_modules"%s',get_host(),server_id,mod_name_str)
	file:write(string.format("'%s'",reload_url))
	file:close()
	print(string.format("'%s'",reload_url))
end

function CMD.handle_reload_result()
	local is_ok = false
	for i = ARGV_HEAD + 1,#ARGV do
		local str = ARGV[i]
		if str == "ok" then
			is_ok = true
			break
		end
	end

	if not is_ok then
		--执行失败
		print("reload faild")
	else
		--执行成功
		print("reload succ")
		os.remove(string.format("./%s.tmp_reload_cmd.txt", load_modsfile))
	end
end

function CMD.try_again_reload()
	local is_ok,str = pcall(file_util.readallfile,string.format("./%s.tmp_reload_cmd.txt", load_modsfile))
	if is_ok then
		print(str)
	end
end

function CMD.check_reload()
	local module_info_dir = "module_info." .. load_modsfile
	local dir_info = lfs.attributes(module_info_dir)
	assert(dir_info and dir_info.mode == 'directory')
	local load_mods = loadfile (load_modsfile)()

	local module_info_map = {}
	for f_name,f_path,f_info in file_util.diripairs(module_info_dir) do
		local m_name = string.sub(f_name,1,#f_name - 9)
		if load_mods[m_name] and f_info.mode == 'file' and string.find(f_name,'.required',nil,true) then
			local f_tb = loadfile(f_path)()
			module_info_map[m_name] = f_tb
		end
	end

	local need_reload_module = {}

  	for module_name,loaded in pairs(module_info_map) do
    	local change_f_name = {}

		for load_f_name,load_f_info in pairs(loaded) do
		local load_f_dir = load_f_info.dir
		local last_change_time = load_f_info.last_change_time
		local now_f_info = lfs.attributes(load_f_dir)
			if now_f_info then
				local new_change_time = now_f_info.modification
				if new_change_time > last_change_time then
					table.insert(change_f_name,load_f_name)
				end
			end
		end

		if #change_f_name > 0 then
			need_reload_module[module_name] = "changefile:" .. table.concat(change_f_name,'|')
		end
  	end

	for module_name,_ in pairs(load_mods) do
		if not module_info_map[module_name] then
		need_reload_module[module_name] = "launch_new_module"
		end
	end

	local old_mod_confg = loadfile(string.format("%s.old", load_modsfile))
	if old_mod_confg then
		old_mod_confg = old_mod_confg()
	end

	if old_mod_confg and next(old_mod_confg) then
		for module_name,module_cfg in pairs(load_mods) do
			local old_module_cfg = old_mod_confg[module_name]
			if old_module_cfg then
			local def_des = table_util.check_def_table(module_cfg,old_module_cfg)
			if next(def_des) then
				need_reload_module[module_name] = table_util.def_tostring(def_des)
			end
			else
			need_reload_module[module_name] = "relaunch module"
			end
		end
	end

	for module_name,change_file in pairs(need_reload_module) do
		print(module_name)
		print(string.format('change_des>>>%s', change_file))
	end
end

function CMD.check_kill_mod()
	local load_mods = loadfile(load_modsfile)()
	local old_mod_confg = loadfile(string.format("%s.old", load_modsfile))
	if not old_mod_confg then
		return	
	end
	old_mod_confg = old_mod_confg()

	for mod_name,_ in pairs(old_mod_confg) do
		if not load_mods[mod_name] then
			print(mod_name)
		end
	end
end

function CMD.call()
	local mod_cmd = assert(ARGV[ARGV_HEAD + 1])
	local server_id = assert(ARGV[#ARGV])

	local mod_cmd_args = ""
	for i = ARGV_HEAD + 2,#ARGV - 1 do
		if tonumber(ARGV[i]) then
			mod_cmd_args = mod_cmd_args .. string.format(',%s',ARGV[i])
		else
			mod_cmd_args = mod_cmd_args .. string.format(',"%s"',ARGV[i])
		end
	end

	local cmd_url = string.format('%s/call/%s/"%s"%s',get_host(),server_id,mod_cmd,mod_cmd_args)
 	print(string.format("'%s'",cmd_url))
end

function CMD.create_load_mods_old()
	local cmd = string.format("cp %s %s.old", load_modsfile, load_modsfile)
	os.execute(cmd)
end

--拷贝一个运行时配置供console.lua读取
function CMD.create_running_config()
	local cmd = string.format("cp %s_config.lua %s_config.lua.%s.run",svr_name, svr_name, load_modsfile)
	os.execute(cmd)
end

--快进时间
function CMD.fasttime()
	local fastdate = ARGV[ARGV_HEAD + 1]
	local one_add = ARGV[ARGV_HEAD + 2]  --单次加速时间 1表示1秒
	assert(fastdate,"not fastdate")
	assert(one_add, "not one_add")
	local date,err = time_util.string_to_date(fastdate)
	if not date then
		error(err)
	end

	local fastcmd = string.format('%s/fasttime/%s/%s',get_host(),os.time(date),one_add)
	print(string.format("'%s'",fastcmd))
end

--检查热更
function CMD.check_hotfix()
	local module_info_dir = "hotfix_info." .. load_modsfile
	local dir_info = lfs.attributes(module_info_dir)
	assert(dir_info and dir_info.mode == 'directory')
	local load_mods = loadfile (load_modsfile)()

	local module_info_map = {}
	for f_name,f_path,f_info in file_util.diripairs(module_info_dir) do
		local m_name = string.sub(f_name,1,#f_name - 9)
		if load_mods[m_name] and f_info.mode == 'file' and string.find(f_name,'.required',nil,true) then
			local f_tb = loadfile(f_path)()
			module_info_map[m_name] = f_tb
		end
	end

	local need_reload_module = {}

  	for module_name,loaded in pairs(module_info_map) do
    	local change_f_name = {}

		for load_f_name,load_f_info in pairs(loaded) do
		local load_f_dir = load_f_info.dir
		local last_change_time = load_f_info.last_change_time
		local now_f_info = lfs.attributes(load_f_dir)
			if now_f_info then
				local new_change_time = now_f_info.modification
				if new_change_time > last_change_time then
					table.insert(change_f_name,load_f_name)
				end
			end
		end

		if #change_f_name > 0 then
			need_reload_module[module_name] = table.concat(change_f_name,'|')
		end
  	end

	for module_name,change_file in pairs(need_reload_module) do
		print(module_name)
		print(change_file)
	end
end

--热更
function CMD.hotfix()
	local load_mods = loadfile(load_modsfile)()
	local server_id = assert(ARGV[ARGV_HEAD + 1])
	local mod_name_str = ",0"
	for i = ARGV_HEAD + 2,#ARGV, 2 do
		local module_name = ARGV[i]
		local hotmods = ARGV[i + 1]
		mod_name_str = mod_name_str .. ',"' .. module_name .. '"'
		mod_name_str = mod_name_str .. ',"' .. hotmods .. '"'
		assert(load_mods[module_name])
	end
	local url = string.format('%s/call/%s/"hotfix"%s',get_host(),server_id,mod_name_str)
	print(string.format("'%s'",url))
end

--解析热更结果
function CMD.handle_hotfix_result()
	local ret = ARGV[ARGV_HEAD + 2]
	print("ret = ",ret)
end

assert(CMD[cmd],'not cmd:' .. cmd)
CMD[cmd]()