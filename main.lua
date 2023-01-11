#!/usr/bin/env luajit
tasker = require('libs.tasker')
telnet = require('libs.telnet')
field = require('libs.field')
menu = require('states.menu')
require('libs.sockman')

local server, ip, port = initServer('*', tonumber(arg[1]) or 2425)
print(('Telnet listener started on: %s:%d'):format(ip, port))

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
		me:send('Your terminal window is too small, resize it please')
		me:send(('\r\nE: (%d, %d)\r\nG: (%d, %d)'):format(
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
			cl, err = acceptClient(server)

			if cl then
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
