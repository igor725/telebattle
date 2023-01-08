local _M = {
	wait = {}
}

function _M:run(tc)
	local function search(me)
		me:fullClear()
		me:send('Searching for opponent...')
		self.wait[me] = true

		while self.wait[me] do
			for otc, waiting in pairs(self.wait) do
				if otc ~= tc and waiting then
					game:new(tc, otc)
					self.wait[tc] = nil
					self.wait[otc] = nil
					return true
				end
			end
			coroutine.yield()
		end

		return true
	end

	local function imenu(title, buttons)
		assert(#buttons < 10, 'Too many options')

		return function(me)
			me:fullClear()
			me:send(title)
			for i = 1, #buttons do
				me:send(('\r\n%d. %s'):format(i, buttons[i].label))
			end

			while true do
				local btn = tonumber(me:waitForInput())
				if btn and buttons[btn] then
					local ret = buttons[btn].func(me)
					if ret ~= nil then
						return ret
					end
				end
			end
		end
	end

	tc:setHandler(imenu('Welcome to the Telnet Battleship!', {
		{label = 'Search for game', func = function(me) return me:setHandler(search) end},
		{label = 'Exit', func = function(me) me:fullClear() me:send('Goodbye!') return false end}
	}))
end

return _M
