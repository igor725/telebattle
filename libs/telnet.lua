local _T = {}
_T.__index = _T

local cmds = {
	IAC = '\xFF',
	-- Telnet actions
	DONT = '\xFE',
	DO = '\xFD',
	WONT = '\xFC',
	WILL = '\xFB',
	SB = '\xFA',
	GOAHEAD = '\xF9',
	BREAK = '\xF3',
	SE = '\xF0',

	-- Telnet commands
	NOP = '\x00',
	ECHO = '\x01',
	SUPP_GO_AHEAD = '\x03',
	TERM = '\x18',
	NAWS = '\x1F',

	-- TERMINAL-TYPE codes
	IS = '\x00',
	SEND = '\x01'
}

function _T:read(count)
	count = tonumber(count)
	local data, err
	local buf = ''

	while not self.dead do
		data, err = self.fd:receive(count)
		if err == 'closed' then
			break
		elseif err == 'timeout' then
			coroutine.yield()
		elseif data then
			count = count - #data
			if count == 0 then
				return buf .. data
			end

			buf = buf .. data
		else
			self:close()
			break
		end
	end

	self.dead = true
end

function _T:close()
	self:showCursor()
	self:disableMouse()
	self.closing = true
end

function _T:isBroken()
	return self.closing or self.dead
end

function _T:send(msg)
	self.sbuffer = self.sbuffer .. tostring(msg)
end

local HAN_ERR = 'Handler must be a function'

function _T:setMouseHandler(func)
	assert(type(func) == 'function', HAN_ERR)
	self.mhandler = func
	return true
end

function _T:setHandler(func)
	assert(type(func) == 'function', HAN_ERR)
	self.handler = func
	return true
end

function _T:decode(...)
	local c = ...
	if not c then return end
	local ret = string.char(c)
	for k, v in pairs(cmds) do
		if v == ret then
			ret = k
			break
		end
	end
	return ret, self:decode(select(2, ...))
end

function _T:sendCommand(...)
	local cmd = ''

	for i = 1, select('#', ...) do
		local ar = select(i, ...)
		if type(ar) == 'number' then
			cmd = cmd .. string.char(ar)
		else
			cmd = cmd .. cmds[ar]
		end
	end

	self:send(cmd)
end

function _T:fullClear()
	self:send('\x1B[2J\x1B[3J\x1B[H\x1B[0m')
end

function _T:isCursorEnabled()
	return self.info.cursor == true
end

function _T:hideCursor()
	local info = self.info
	if info.cursor then
		self:send('\x1B[?25l')
		info.cursor = false
	end
end

function _T:showCursor()
	local info = self.info
	if not info.cursor then
		self:send('\x1B[?25h')
		info.cursor = true
	end
end

function _T:toggleCursor()
	if self:isCursorEnabled() then
		self:hideCursor()
	else
		self:showCursor()
	end
end

function _T:saveScreen()
	self:send('\x1B[?47h')
end

function _T:restoreScreen()
	self:send('\x1B[?47l')
end

function _T:setCurPos(x, y)
	self:send(('\x1B[%d;%dH'):format(
		math.ceil(tonumber(y) or 1),
		math.ceil(tonumber(x) or 1)
	))
end

function _T:clearFromCur(x, y)
	if x and y then
		self:setCurPos(x, y)
	end
	self:send('\x1B[K')
end

function _T:textOn(x, y, text)
	self:setCurPos(x, y)
	self:text(text)
end

function _T:text(text)
	self:send(tostring(text):gsub('(.?)(%^[%+%-]?.)', function(p, c)
		if p == '%' then
			return c
		end

		local bm = c:byte(2)
		if bm == 0x52 then
			return p .. '\x1B[0m'
		end

		assert(bm == 0x2B or bm == 0x2D, 'Unknown switch')
		local m = bm == 0x2B
		local b = c:byte(3)

		if b == 0x69 then -- Italic
			return p .. (m and '\x1B[3m' or '\x1B[23m')
		elseif b == 0x75 then -- Underline
			return p .. (m and '\x1B[4m' or '\x1B[24m')
		elseif b == 0x62 then -- Bold
			return p .. (m and '\x1B[1m' or '\x1B[22m')
		elseif b == 0x66 then -- Faint
			return p .. (m and '\x1B[2m' or '\x1B[22m')
		elseif b == 0x73 then -- Strikethrough
			return p .. (m and '\x1B[9m' or '\x1B[29m')
		elseif b == 0x69 then -- Inverse
			return p .. (m and '\x1B[7m' or '\x1B[29m')
		elseif b == 0x68 then -- Hidden
			return p .. (m and '\x1B[8m' or '\x1B[28m')
		elseif b == 0x6C then -- bLink
			return p .. (m and '\x1B[5m' or '\x1B[25m')
		else
			error('Unknown mode')
		end
	end))
end

function _T:waitForInput(signal)
	repeat
		coroutine.yield()

		if self:isBroken() then
			return nil, 'closed'
		elseif signal and signal:isSignaled() then
			return nil, 'signaled'
		end
	until self.lastkey ~= nil

	return self.lastkey
end

function _T:lastInput()
	return self.lastkey
end

function _T:getDimensions()
	if not self.modes.naws then
		return 0, 0
	end

	local info = self.info
	return info.width, info.height
end

function _T:getTerminal()
	if not self.modes.term then
		return 'unknown'
	end

	return self.info.term
end

function _T:waitForDimsChange(signal)
	local w, h = self:getDimensions()
	if w == 0 or h == 0 then return 0, 0 end

	while not self:isBroken() do
		local nw, nh = self:getDimensions()
		if nw ~= w or nh ~= h then
			return nw, nh
		end

		coroutine.yield()
		if signal and signal:isSignaled() then
			return w, h, 'signaled'
		end
	end

	return w, h
end

function _T:isMouseEnabled()
	return self.modes.mouse == true
end

function _T:getMouseState()
	return self.info.mouse
end

function _T:disableMouse()
	local modes = self.modes
	if modes.mouse then
		modes.mouse = false
		self.info.mouse = nil
		self:send('\x1B[?1000l')
	end
end

function _T:enableMouse()
	local modes = self.modes
	if not modes.mouse then
		self.info.mouse = {x = 0, y = 0, whl = 0, lmb = false, mmb = false, rmb = false}
		self:send('\x1B[?1003h\x1B[?1015h\x1B[?1006h')
	end
end

function _T:toggleMouse()
	if self:isMouseEnabled() then
		self:disableMouse()
	else
		self:enableMouse()
	end
end

function _T:supportColors()
	return self.modes.colors == true
end

function _T:enableColors(val)
	local info = self.info
	info.colors = (val == true) or (val == nil)
	return info.colors
end

function _T:hasColors()
	return self.info.colors == true
end

function _T:putColor(color)
	if self:hasColors() then
		local ct = type(color)
		if ct == 'string' or ct == 'number' then
			self:send('\x1B[' .. tostring(color) .. 'm')
			return
		end

		self:send('\x1B[39;49m')
	end
end

local keys = {
	['A'] = 'aup',
	['B'] = 'adown',
	['C'] = 'aright',
	['D'] = 'aleft',
	['P'] = 'pause',
	['1~'] = 'home',
	['2~'] = 'insert',
	['4~'] = 'end',
	['5~'] = 'pgup',
	['6~'] = 'pgdn',
}

local negotiators = {
	[cmds.NAWS] = function(tc)
		local info = tc.info
		local b1, b2, b3, b4 = tc:read(4):byte(1, -1)
		info.width, info.height = b1 * 256 + b2, b3 * 256 + b4
		return false
	end,
	[cmds.TERM] = function(tc)
		assert(tc:read(1) == cmds.IS)
		local name = ''
		while true do
			local char = tc:read(1)

			if char ~= cmds.IAC then
				name = name .. char
				assert(#name < 32, 'Terminal name is too long')
			else
				assert(tc:read(1) == cmds.SE)
				name = name:lower()
				tc.info.term = name
				tc.modes.colors = name:find('xterm', 1, true) ~= nil or
								  name:find('color', 1, true) ~= nil or
								  name:find('vt100', 1, true) ~= nil or
								  name:find('linux', 1, true) ~= nil
				return true
			end
		end
	end
}

local endsym = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ~>=cfghijklmnopqrstuvwxyz'

function _T:configure(dohs)
	local fd = self.fd

	local function fuckit(coro, err)
		fd:send('\x1B[2J\x1B[H\r\nTelnet panic screen')
		if type(GIT_COMMIT) == 'string' then
			fd:send(' (commit: ')
			fd:send(GIT_COMMIT)
			fd:send(')')
		end
		fd:send('\r\n')
		fd:send(tasker.defErrHand(coro, err))
		self.dead = true
		fd:close()
	end

	tasker:newTask(function()
		while not self.dead do
			local sbuf = self.sbuffer
			local bufsz = #sbuf

			if bufsz > 0 then
				local spos, err = fd:send(sbuf)
				if err == 'closed' then
					break
				elseif err ~= nil then
					coroutine.yield()
				end

				self.sbuffer = self.sbuffer:sub(spos + 1)
			elseif self.closing then
				break
			else
				coroutine.yield()
			end
		end

		fd:close()
		self.fd = nil
		self.dead = true
	end, fuckit)

	tasker:newTask(function()
		if dohs then
			self:sendCommand(
				'IAC', 'DO', 'NAWS',
				'IAC', 'DO', 'TERM'
			)

			local timeout = gettime() + 2
			local modes = self.modes
			while modes.term == nil or modes.naws == nil do
				coroutine.yield()

				if gettime() > timeout then
					self:close()
				end

				if self:isBroken() then
					self:close()
					return
				end
			end

			local info = self.info
			if modes.term then
				while info.term == nil do
					coroutine.yield()

					if gettime() > timeout then
						self:close()
					end

					if self:isBroken() then
						self:close()
						return
					end
				end
			end
			if modes.naws then
				while info.width == nil do
					coroutine.yield()

					if gettime() > timeout then
						self:close()
					end

					if self:isBroken() then
						self:close()
						return
					end
				end
			end
		end

		while type(self.handler) == 'function' and self.handler(self) do
			if self.closing or self.dead then
				break
			end
		end

		self:close()
	end, fuckit)

	tasker:newTask(function()
		local subnego

		while not self.dead do
			self.lastkey = nil

			if subnego and subnego(self) then
				subnego = nil
			end

			local ch = self:read(1)
			if not ch then
				break
			end
			local chb = ch:byte()

			if chb == 0x1B then
				local es = self:read(1)
				if es == '[' then
					local act = self:read(1)
					if not endsym:find(act, 1, true) then
						while true do
							local nch = self:read(1)
							act = act .. nch
							if endsym:find(nch, 1, true) then break end
						end
					end
					local key = keys[act]
					if key then
						self.lastkey = key
					elseif act:byte() == 0x3C then
						local mouse = self.info.mouse
						if mouse then
							local cmd, xpos, ypos, mod = act:match('<(%d+);(%d+);(%d+)([Mm])')
							if cmd then
								cmd, xpos, ypos = tonumber(cmd), tonumber(xpos), tonumber(ypos)
								mouse.x, mouse.y = xpos, ypos
								mod = mod == 'M'
								mouse.whl = 0

								if cmd == 0 then
									mouse.lmb = mod
								elseif cmd == 1 then
									mouse.mmb = mod
								elseif cmd == 2 then
									mouse.rmb = mod
								elseif cmd == 64 then
									mouse.whl = 1
								elseif cmd == 65 then
									mouse.whl = -1
								elseif cmd ~= 35 then
									io.stderr:write('Unhandled mouse event:', act, '\r\n')
								end

								local mhan = self.mhandler
								if type(mhan) == 'function' then
									mhan(mouse)
								end
							end
						end
					else
						io.stderr:write('Unhandled escape sequence:', act, '\r\n')
					end
				end
			elseif chb < 0x20 then
				if ch ~= '\n' then
					if ch == '\3' then
						self.lastkey = 'ctrlc'
					elseif ch == '\8' then
						self.lastkey = 'backspace'
					elseif ch == '\t' then
						self.lastkey = 'tab'
					elseif ch == '\r' then
						self.lastkey = 'enter'
					end
				end
			elseif chb == 0x20 then
				self.lastkey = 'space'
			elseif chb >= 0x21 and chb <= 0x7E then -- ASCII symbols
				self.lastkey = ch
			elseif chb == 0x7F then -- Another backspace
				self.lastkey = 'backspace'
			elseif chb == 0xFF then -- IAC
				local act = self:read(1)

				if act == cmds.SB then -- Telnet wants to start negotiation
					local opt = self:read(1)
					subnego = negotiators[opt]
					if subnego then
						self:sendCommand('IAC', 'GOAHEAD')
					else
						self:sendCommand('IAC', 'WONT', opt:byte())
					end
				elseif act == cmds.SE then -- Telnet wants to end negotiation
					subnego = nil
				elseif act == cmds.WILL then -- Telnet wants to do something
					local cmd = self:read(1)
					if cmd == cmds.NAWS then
						self.modes.naws = true
					elseif cmd == cmds.TERM then
						self.modes.term = true
						self:sendCommand('IAC', 'SB', 'TERM', 'SEND', 'IAC', 'SE')
					end
				elseif act == cmds.WONT then -- Telnet doesn't want to do something
					local cmd = self:read(1)
					if cmd == cmds.NAWS then
						self.modes.naws = true
					elseif cmd == cmds.TERM then
						self.modes.term = false
					end
				elseif act == cmds.DO then -- Telnet does something, we don't care much about it
					self:read(1)
				else
					io.stderr:write(('Unhandled telnet action: %X\r\n'):format(act:byte()))
				end
			end

			if self.lastkey then
				coroutine.yield()
			end
		end
	end, fuckit)

	self.configure = false
	return self
end

return {
	_NAME = 'telnet.lua',
	_VERSION = '0.1',
	_LICENSE = 'MIT',

	init = function(fd, dohs)
		return setmetatable({
			info = {
				cursor = true,
				colors = false
			},
			modes = {
				colors = false,
				mouse = false
			},
			closed = false,
			sbuffer = '',
			fd = fd
		}, _T):configure(dohs)
	end,

	genMenu = function(title, buttons)
		assert(#buttons < 10, 'Too many options')

		return function(me)
			me:fullClear()
			if type(title) == 'function' then
				me:text(tostring(title(me)))
			else
				me:text(tostring(title))
			end

			for i = 1, #buttons do
				local blabel = buttons[i].label
				if type(blabel) == 'function' then
					blabel = blabel(me)
				end
				me:text(('\r\n%d. %s'):format(i, tostring(blabel)))
			end

			while not me:isBroken() do
				local btn, err = me:waitForInput()
				if err then return false end
				btn = tonumber(btn)

				if btn and buttons[btn] then
					local ret = buttons[btn].func(me)
					if ret ~= nil then
						return ret
					end
				end
			end
		end
	end
}
