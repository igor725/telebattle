local _T = {}
_T.__index = _T
local cmds = {
	ECHO = '\x01',
	SUPP_GO_AHEAD = '\x03',
	SUPP_ECHO = '\x2D',
	TERM = '\x18',
	NAWS = '\x1F',

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
	local buf = ''

	while not self.dead do
		local data, err, pdata = self.fd:receive(count or '*a')
		if err == 'closed' then
			break
		end
		if err == 'timeout' then
			coroutine.yield()
		end
		if data then
			return buf .. data
		end
		if pdata then
			if not count then
				return pdata
			end
			buf = buf .. pdata
			if count then
				count = count - #pdata
				if count == 0 then
					return buf
				end
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
	while true do
		coroutine.yield()

		if self.lastchar ~= nil then
			return self.lastchar
		elseif self.lastkey ~= nil then
			return self.lastkey
		end
	end
end

function _T:getDimensions()
	local info = self.info
	return info.width, info.height
end

function _T:waitForDimsChange()
	local w, h = self:getDimensions()

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
	['D'] = 'aleft',
	['C'] = 'aright',
	['A'] = 'aup',
	['B'] = 'adown',
}

local negotiators = {
	[0x1F] = function(self)
		local info = self.info
		local b1, b2, b3, b4 = self:read(4):byte(1, -1)
		info.width, info.height = b1 * 256 + b2, b3 * 256 + b4
	end
}

function _T:configure()
	local fd = self.fd
	fd:setoption('tcp-nodelay', true)
	fd:settimeout(0)

	local function fuckit(err)
		fd:send('\x1B[2J\x1B[H' .. err)
		self.dead = true
		fd:close()
	end

	tasker:newTask(function()
		local subneog

		while not self.dead do
			self.lastchar, self.lastkey = nil, nil

			if subneog then
				subneog(self)
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
				self.lastchar = ch
			elseif chb == 0xFF then -- IAC
				local act = self:read(1)

				if act == cmds.SB then -- Telnet wants to start negotiation
					local opt = self:read(1):byte()
					subneog = negotiators[opt]
					if subneog then
						self:sendCommand('IAC', 'GOAHEAD')
					else
						self:sendCommand('IAC', 'WONT', opt)
					end
				elseif act == cmds.SE then -- Telnet wants to end negotiation
					subneog = nil
				elseif act == cmds.WILL then -- Telnet wants to do something
					local cmd = self:read(1)
					if cmd == cmds.NAWS then
						self.modes.naws = true
					end
				elseif act == cmds.WONT then -- Telnet doesn't want to do something
					local cmd = self:read(1)
					if cmd == cmds.NAWS then
						self.modes.naws = true
					end
				elseif act == cmds.DO then -- Telnet does something
					self:read(1)
				else
					print(('Unhandled telnet action: %X'):format(act:byte()))
				end
			end

			if self.lastchar or self.lastkey then
				coroutine.yield()
			end
		end
	end, fuckit)

	tasker:newTask(function()
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

function _T:init(fd)
	return setmetatable({
		info = {
			width = 0, height = 0,
			terminal = 'unknown'
		},
		modes = {
			naws = false
		},
		closed = false,
		sbuffer = '',
		spos = 1,
		fd = fd
	}, self):configure()
end

return _T
