local _T = {
	list = {},
	onerror = {}
}

local sleep = socket.sleep

function _T.sleep(sec)
	local time = socket.gettime() + sec
	while socket.gettime() < time do
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
			end
		end
	end
end

function _T:runLoop()
	while true do
		self:update()
		sleep(0.001)
	end
end

return _T
