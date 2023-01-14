local _O = {
	online = 0,
	tmax = os.time(),
	max = 0
}

function _O:install(me)
	tasker:newTask(function()
		self.online = self.online + 1

		if os.time() - self.tmax >= 86400 then
			self.max = self.online
			self.tmax = os.time()
		else
			self.max = math.max(self.max, self.online)
		end

		while not me:isBroken() do
			coroutine.yield()
		end

		self.online = self.online - 1
	end)
end

function _O:getText()
	return ('Online: %d | Max 24h: %d'):format(self.online, self.max)
end

return _O
