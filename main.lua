#!/usr/bin/env luajit
ljsocket = require('libs.thirdparty.ljsocket')
tasker = require('libs.tasker')
telnet = require('libs.telnet')
field = require('libs.field')
menu = require('states.menu')

local info = ljsocket.find_first_address('*', tonumber(arg[1]) or 2425)
if not info then print('No adapter found') return 1 end
server = ljsocket.create(info.family, info.socket_type, info.protocol)
server:set_blocking(false)
assert(server:set_option('nodelay', true, 'tcp'))
assert(server:set_option('reuseaddr', true))
assert(server:bind(info))
assert(server:listen())
print(('Telnet listener started on: %s:%d'):format(info:get_ip(), info:get_port()))

local function init(me)
	me:sendCommand(
		'IAC', 'WILL', 'ECHO',
		'IAC', 'WILL', 'SUPP_GO_AHEAD'
	)
	me:send('Waiting for telnet to respond...')

	local ww, wh = me:getDimensions()
	local fw, fh = field.getDimensions()
	fw, fh = fw * 3, fh + 4

	while wh < fh or ww < fw do
		me:fullClear()
		me:send(('Your terminal window is too small, resize it please\r\nE: (%d, %d)\r\nG: (%d, %d)'):format(
			fw, fh, ww, wh
		))

		ww, wh = me:waitForDimsChange()
		if me:isBroken() then
			return false
		end

		coroutine.yield()
	end

	return menu:run(me)
end

tasker:newTask(function()
	math.randomseed(os.time())
	local run = true

	while run do
		local cl
		repeat
			cl, err = server:accept()
			if cl then
				assert(cl:set_blocking(false))
				telnet:init(cl, true)
				:setHandler(init)
			elseif err ~= 'timeout' then
				run = false
			end
		until cl == nil

		coroutine.yield()
	end

	print('Server socket suddenly died')
	os.exit(1)
end, error)

tasker:runLoop()
