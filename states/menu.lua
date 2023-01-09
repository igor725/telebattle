local _M = {
	wait = {},
	priv = {},
	start = os.time()
}

function _M:run(tc)
	local function search(me)
		me:fullClear()
		me:send('Searching for opponent...\r\nPress Ctrl+C to return to the main menu')
		self.wait[me] = true

		while self.wait[me] do
			if me:lastInput() == 'ctrlc' then
				return self:run(me)
			end

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

	local ctrlctext = '\r\nOr press Ctrl+C to return to the main menu'

	local function friends_host(me)
		me:fullClear()
		local id = self.start
		repeat
			id = id + 1
		until self.priv[id] == nil
		me:send(('Your room id is %d'):format(id))
		me:send('\r\nTell this number to your friend you want play with')
		me:send(ctrlctext)
		self.priv[id] = me

		while self.priv[id] == me do
			if me:lastInput() == 'ctrlc' then
				return self:run(me)
			end

			coroutine.yield()
		end

		return true
	end
	local function friends_enter(me)
		local id = ''
		me:fullClear()
		me:send('Enter room id your friend just told you:')
		me:send(ctrlctext)
		me:setCurPos(42, 1)

		while true do
			local key = me:waitForInput()
			if key == 'enter' then
				me:clearFromCur(42, 1)
				id = tonumber(id)
				local opp = self.priv[id]
				if opp then
					game:new(me, opp)
					self.priv[id] = nil
					return true
				end

				id = ''
			elseif key == 'backspace' then
				if #id > 0 then
					id = id:sub(1, -2)
					me:send('\8 \8')
				end
			elseif key == 'ctrlc' then
				return self:run(me)
			elseif #key == 1 then
				local kb = key:byte()
				if kb >= 48 and kb <= 57 then
					me:send(key)
					id = id .. key
				end
			end
		end
	end

	local friends = telnet.genMenu('Play with friend', {
		{label = 'Host a game', func = friends_host},
		{label = 'Enter an existing game', func = friends_enter},
		{label = 'Go back', func = function(me) return self:run(me) end}
	})

	return tc:setHandler(telnet.genMenu('Welcome to the Telnet Battleship!', {
		{label = 'Search for game', func = function(me) return me:setHandler(search) end},
		{label = 'Play with a friend', func = function(me) return me:setHandler(friends) end},
		{label = 'Exit', func = function(me) me:fullClear() me:send('Goodbye!') return false end}
	}))
end

return _M
