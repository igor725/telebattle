local co_create = coroutine.create
local co_resume = coroutine.resume
local co_yield = coroutine.yield
local dbg_trace = debug.traceback
local tab_insert = table.insert
local tab_remove = table.remove
local io_stderr = io.stderr
local gettime = _G.gettime
local sleep = _G.sleep

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
				co_yield()
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
				co_yield()
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
		coro, err, dbg_trace(coro):gsub('\n', '\r\n')
	)
	io_stderr:write(fmts)
	return fmts
end

function _T.sleep(sec, signal)
	local time = gettime() + sec
	while gettime() < time and (not signal or not signal:signaled()) do
		co_yield()
	end
	return true
end

function _T:newTask(func, errh)
	local coro = co_create(function()
		func() return true
	end)
	tab_insert(self.list, coro)
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

function _T:runLoop()
	local coros = self.list

	while true do
		local start = gettime()
		for i = #coros, 1, -1 do
			local coro = coros[i]
			local ret, st = co_resume(coro)
			if ret == false or st == true then
				tab_remove(coros, i)
				if ret == false then
					local errh = self.onerror[coro] or self.defErrHand
					if errh then pcall(errh, coro, st)end
					self.onerror[coro] = nil
				end
			end
		end
		local elap = gettime() - start
		if elap < 0.031 then
			sleep(0.031 - elap)
		end
	end
end

return _T
