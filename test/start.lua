local boot = require "ltask.bootstrap"
local ltask = require "ltask"

local SERVICE_ROOT <const> = 1
local MESSSAGE_SYSTEM <const> = 0

local config

local function searchpath(name)
	return assert(package.searchpath(name, config.service_path))
end

local function readall(path)
	local f <close> = assert(io.open(path))
	return f:read "a"
end

local function init_config()
	local servicepath = searchpath "service"
	config.service_source = config.service_source or readall(servicepath)
	config.service_chunkname = config.service_chunkname or ("@" .. servicepath)
	config.initfunc = ([=[
local name = ...
package.path = [[${lua_path}]]
package.cpath = [[${lua_cpath}]]
local filename, err = package.searchpath(name, "${service_path}")
if not filename then
	return nil, err
end
return loadfile(filename)
]=]):gsub("%$%{([^}]*)%}", {
	lua_path = config.lua_path or package.path,
	lua_cpath = config.lua_cpath or package.cpath,
	service_path = config.service_path,
})
end

local function new_service(label, id)
	local sid = assert(boot.new_service(label, config.service_source, config.service_chunkname, id))
	assert(sid == id)
	return sid
end

local function bootstrap()
	new_service("root", SERVICE_ROOT)
	boot.init_root(SERVICE_ROOT)
	-- send init message to root service
	local init_msg, sz = ltask.pack("init", {
		initfunc = config.initfunc,
		name = "root",
		args = {config}
	})
	-- self bootstrap
	boot.post_message {
		from = SERVICE_ROOT,
		to = SERVICE_ROOT,
		session = 0,	-- 0 for root init
		type = MESSSAGE_SYSTEM,
		message = init_msg,
		size = sz,
	}
end

local function exclusive_thread(label, id)
	local sid = new_service(label, id)
	boot.new_thread(sid)
end

function print(...)
	boot.pushlog(ltask.pack("info", ...))
end

-- test exclusive transfer

local function dummy_service(id)
	local dummy = [[
local exclusive = require "ltask.exclusive"

local i = 0
while true do
	local pre = coroutine.yield()
	print ("Dummy Tick", pre, i)
	io.flush()
	exclusive.sleep(1000)
	i = i + 1
end
	]]

	local p = boot.preinit(dummy)
	local label = "Dummy"
	os.execute "sleep 1"

	local sid = assert(boot.new_service_preinit(label, id + 1, p))
	assert(id + 1 == sid)
	boot.new_thread(sid)
end

local function start(cfg)
	config = cfg
	init_config()
	boot.init(config)
	boot.init_timer()
	boot.init_socket()

	local id = 0
	for i, label in ipairs(config.exclusive) do
		id = i + 1
		exclusive_thread(label, id)
	end
	-- dummy_service(id)
	bootstrap()	-- launch root
	print "ltask Start"
	local ctx = boot.run()
	boot.wait(ctx)
	boot.deinit()
end

return start
