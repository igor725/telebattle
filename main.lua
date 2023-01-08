local PORT = tonumber(arg[1]) or 2425

socket = require('socket.core')
tasker = require('libs.tasker')
telnet = require('libs.telnet')
placer = require('libs.placer')
field = require('libs.field')
hint = require('libs.hint')
game = require('states.game')
menu = require('states.menu')

server = socket.tcp()
server:settimeout(0)
server:setoption('reuseaddr', true)
server:setoption('tcp-nodelay', true)
assert(server:bind('0.0.0.0', PORT))
assert(server:listen())
io.write('Telnet listener startd on *:', PORT, '\r\n')

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
	end

	return menu:run(me)
end

tasker:newTask(function()
	math.randomseed(os.time())

	while true do
		local cl
		repeat
			cl = server:accept()
			if cl then
				cl:settimeout(0)
				telnet:init(cl, true)
				:setHandler(init)
			end
		until cl == nil

		coroutine.yield()
	end
end, error)

tasker:runLoop()
