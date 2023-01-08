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
			me:read()
			coroutine.yield()
		end

		return true
	end

	tc:setHandler(function(me)
		me:fullClear()
		me:send('Welcome to the Telnet Battleship!\r\n1. Search for game\r\n2. Exit\r\n')

		while true do
			local inp = me:read(1)
			if inp == '1' then
				me:setHandler(search)
				return true
			elseif inp == '2' then
				me:send('Goodbye!')
				break
			end
		end
	end)
end

return _M
