local _T = {
	list = {},
	onerror = {},
	signal = {
		signal = function(self)
			self.signaled = true
		end,
		reset = function(self)
			self.signaled = false
		end,
		wait = function(self)
			while not self.signaled do
				coroutine.yield()
			end

			return true
		end,
		isSignaled = function(self)
			return self.signaled
		end
	},
	timeout = {
		reset = function(self, time)
			time = (type(time) == 'number' and time or self.time) or 0
			self.timeout = gettime() + time
			self.time = time
			return self
		end,
		wait = function(self, reset)
			while gettime() < self.timeout do
				coroutine.yield()
			end

			if reset then
				self:reset()
			end

			return true
		end,
		isSignaled = function(self)
			return gettime() < self.timeout
		end
	}
}
_T.signal.__index = _T.signal
_T.timeout.__index = _T.timeout

function _T.defErrHand(coro, err)
	local fmts = ('coroutine[%p] died: %s\r\n%s\r\n'):format(
		coro, err, debug.traceback(coro):gsub('\n', '\r\n')
	)
	io.stderr:write(fmts)
	return fmts
end

function _T.sleep(sec)
	local time = gettime() + sec
	while gettime() < time do
		coroutine.yield()
	end
	return true
end

function _T:newTask(func, errh)
	local coro = coroutine.create(function()
		func() return true
	end)
	table.insert(self.list, coro)
	self.onerror[coro] = errh
end

function _T:newSignal()
	return setmetatable({
		signaled = false
	}, self.signal)
end

function _T:newTimeout(init)
	return setmetatable({}, self.timeout):reset(init)
end

function _T:update()
	local coros = self.list
	for i = #coros, 1, -1 do
		local coro = coros[i]
		local ret, st = coroutine.resume(coro)
		if ret == false or st == true then
			table.remove(coros, i)
			if ret == false then
				local errh = self.onerror[coro] or tasker.defErrHand
				if errh then pcall(errh, coro, st)end
				self.onerror[coro] = nil
			end
		end
	end
end

function _T:getCount()
	return #self.list
end

function _T:runLoop()
	while true do
		local start = gettime()
		self:update()
		local elap = gettime() - start
		if elap < 0.031 then
			sleep(0.031 - elap)
		end
	end
end

return _T
