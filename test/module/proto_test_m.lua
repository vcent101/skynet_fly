local log = require "skynet-fly.log"
local timer = require "skynet-fly.timer"
local skynet = require "skynet"
local pb_netpack = require "skynet-fly.netpack.pb_netpack"

local CMD = {}

function CMD.start()
	log.error("proto_test_m start!!!")

	log.info(pb_netpack.load("./proto"))

	local login_req = {
		player_id = 100001,
		nickname = "skynet_fly",
		password = "123456",
		account = "skynet",
	}

	local ok,pb_str = pb_netpack.encode(".login.LoginReq",login_req)
	log.info("pb.encode:",ok,pb_str)

	log.info("pb.decode:",pb_netpack.decode(".login.LoginReq",pb_str))

	log.error("proto_test_m start!!!")
	return true
end

function CMD.exit()
	return true
end

return CMD