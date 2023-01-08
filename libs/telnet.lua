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

function _T:read(count, wait)
	count = tonumber(count)
	local buf = ''

	while not self.dead and not self.closing do
		if wait and wait:isSignaled()then
			return nil, 'signaled'
		end

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
		cmd = cmd .. cmds[ar]
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

function _T:configure()
	local fd = self.fd
	fd:setoption('tcp-nodelay', true)
	fd:settimeout(0)

	local function fuckit(err)
		fd:send('\x1B[2J\x1B[H' .. err)
		fd:close()
	end

	tasker:newTask(function()
		while self.handler and self.handler(self) do
			if self.closing or self.dead then
				break
			end
		end

		self.closing = true
	end, fuckit)

	tasker:newTask(function()
		while true do
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
		closed = false,
		sbuffer = '',
		spos = 1,
		fd = fd
	}, self):configure()
end

return _T
