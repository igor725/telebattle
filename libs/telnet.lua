local _T = {}
_T.__index = _T
local cmds = {
	ECHO = '\x01',
	SUPP_GO_AHEAD = '\x03',
	SUPP_ECHO = '\x2D',
	TERM = '\x18',
	NAWS = '\x1F',

	-- TERMINAL-TYPE codes
	IS = '\x00',
	SEND = '\x01',

	SE = '\xF0',
	BREAK = '\xF3',
	GOAHEAD = '\xF9',
	SB = '\xFA',
	WILL = '\xFB',
	WONT = '\xFC',
	DO = '\xFD',
	DONT = '\xFE',
	IAC = '\xFF',

	VT = '\x1B[',
	HOME = 'H',
	CLEAR = '2J',
	RESET = '0m'
}

function _T:read(count)
	count = tonumber(count)
	local buf, data, err = ''

	while not self.dead do
		data, err, buf = self.fd:receive(count or '*a', buf)
		if err == 'closed' then
			break
		end
		if err == 'timeout' then
			coroutine.yield()
		end
		if data then
			return data
		end
		if buf then
			if not count then
				return buf
			end
			if count and count == #buf then
				return buf
			end
		end
		coroutine.yield()
	end

	self.dead = true
end

function _T:close()
	self.closing = true
end

function _T:isBroken()
	self:read()
	return self.closing or self.dead
end

function _T:send(msg)
	self.sbuffer = self.sbuffer .. tostring(msg)
end

function _T:setHandler(func)
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
	self:sendCommand('VT', 'CLEAR', 'VT', 'HOME')
end

function _T:setCurPos(x, y)
	self:send(('\x1B[%d;%dH'):format(
		math.ceil(tonumber(y)),
		math.ceil(tonumber(x))
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
	self:send(text)
end

function _T:waitForInput()
	repeat
		coroutine.yield()
	until self.lastkey ~= nil

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

function _T:waitForDimsChange()
	local w, h = self:getDimensions()
	if w == 0 or h == 0 then return 0, 0 end

	while not self.dead do
		local nw, nh = self:getDimensions()
		if nw ~= w or nh ~= h then
			return nw, nh
		end

		coroutine.yield()
	end

	return w, h
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
			else
				assert(tc:read(1) == cmds.SE)
				tc.info.term = name
				return true
			end
		end
	end
}

local endsym = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ~<>='

function _T:configure(dohs)
	local fd = self.fd
	fd:setoption('tcp-nodelay', true)
	fd:settimeout(0)

	local function fuckit(err)
		fd:send('\x1B[2J\x1B[H' .. err)
		self.dead = true
		fd:close()
	end

	tasker:newTask(function()
		local subnego

		while not self.dead do
			self.lastkey = nil

			if subnego and subnego(self) then
				subnego = nil
			end

			local ch = self:read(1)
			if not ch then
				self.dead = true
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
					else
						print('Unhandled escape sequence:', act)
					end
				end
			elseif chb < 0x20 then
				if ch ~= '\r' then
					if ch == '\3' then
						self.lastkey = 'ctrlc'
					elseif ch == '\t' then
						self.lastkey = 'tab'
					elseif ch == '\n' then
						self.lastkey = 'enter'
					end
				end
			elseif chb >= 0x20 and chb <= 0x7F then -- ASCII symbol
				self.lastkey = ch
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
					print(('Unhandled telnet action: %X'):format(act:byte()))
				end
			end

			if self.lastkey then
				coroutine.yield()
			end
		end
	end, fuckit)

	tasker:newTask(function()
		if dohs then
			self:sendCommand(
				'IAC', 'DO', 'NAWS',
				'IAC', 'DO', 'TERM'
			)

			local modes = self.modes
			while modes.term == nil or modes.naws == nil do
				coroutine.yield()
			end

			local info = self.info
			if modes.term then
				while info.term == nil do
					coroutine.yield()
				end
			end
			if modes.naws then
				while info.width == nil do
					coroutine.yield()
				end
			end
		end

		while self.handler and self.handler(self) do
			if self.closing or self.dead then
				break
			end
		end

		self.closing = true
	end, fuckit)

	tasker:newTask(function()
		while not self.dead do
			local sbuf = self.sbuffer
			local bufsz = #sbuf

			if bufsz > 0 then
				local spos, err = self.spos
				spos, err = fd:send(sbuf, spos)
				if err then
					coroutine.yield()
				elseif err == 'closed' then
					break
				end

				if bufsz == spos then
					self.sbuffer = ''
					self.spos = 1
				else
					self.spos = spos
				end
			elseif self.closing then
				break
			end

			coroutine.yield()
		end

		self.dead = true
		fd:close()
	end, fuckit)

	self.configure = false
	return self
end

function _T:init(fd, dohs)
	return setmetatable({
		info = {},
		modes = {},
		closed = false,
		sbuffer = '',
		spos = 1,
		fd = fd
	}, self):configure(dohs)
end

return _T
