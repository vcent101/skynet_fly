local skynet = require "skynet"
local contriner_launcher = require "skynet-fly.contriner.contriner_launcher"

skynet.start(function()
	skynet.error("start cluster_client_byredis!!!>>>>>>>>>>>>>>>>>")
	contriner_launcher.run()
	
	skynet.exit()
end)