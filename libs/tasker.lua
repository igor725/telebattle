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
		end,
		isSignaled = function(self)
			return self.signaled
		end
	}
}
_T.signal.__index = _T.signal

function _T.sleep(sec)
	local time = gettime() + sec
	while gettime() < time do
		coroutine.yield()
	end
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

function _T:update()
	local coros = self.list
	for i = #coros, 1, -1 do
		local coro = coros[i]
		local ret, st = coroutine.resume(coro)
		if ret == false or st == true then
			table.remove(coros, i)
			if ret == false then
				print('coro error', coro, st)
				local errh = self.onerror[coro]
				if errh then pcall(errh, st)end
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
