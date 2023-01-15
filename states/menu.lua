local _M = {
	wait = {},
	priv = {},
	motd = {},
	start = os.time()
}

function _M:init()
	local motd = io.open('motd.txt', 'r')
	if motd then
		for line in motd:lines() do
			table.insert(self.motd, line)
		end
		motd:close()
	end
end

function _M:run(tc)
	local searchstate, friendsmenu,
	mainmenu, aboutmessage
	local closed = false

	searchstate = function(me)
		me:fullClear()
		me:send('Searching for opponent...\r\nPress Ctrl+C to return to the main menu')
		self.wait[me] = true

		while self.wait[me] do
			if me:lastInput() == 'ctrlc' then
				self.wait[me] = nil
				return me:setHandler(mainmenu)
			end

			for otc, waiting in pairs(self.wait) do
				if otc ~= tc and waiting then
					require('states.game'):new(tc, otc)
					self.wait[tc] = nil
					self.wait[otc] = nil
					closed = true
					return true
				end
			end

			coroutine.yield()
		end

		closed = true
		return true
	end

	local ctrlctext = '\r\nOr press Ctrl+C to return to the main menu'

	local function friends_host(me)
		me:fullClear()
		local id = 0
		repeat
			id = id + 1
		until self.priv[id] == nil
		me:send(('Your room id is %d'):format(self.start + id))
		me:send('\r\nTell this number to your friend you want play with')
		me:send(ctrlctext)
		self.priv[id] = me

		while self.priv[id] == me do
			if me:lastInput() == 'ctrlc' then
				self.priv[id] = nil
				return me:setHandler(mainmenu)
			end

			coroutine.yield()
		end

		closed = true
		return true
	end

	local function friends_enter(me)
		local id = ''
		me:fullClear()
		me:showCursor()
		me:send('Enter room id your friend just told you:')
		me:send(ctrlctext)
		me:setCurPos(42, 1)

		while true do
			local key = me:waitForInput()

			if key == nil then
				break
			elseif key == 'enter' then
				me:clearFromCur(42, 1)
				local nid = tonumber(id)
				id = ''

				if nid then
					nid = nid - self.start
					local opp = self.priv[nid]
					if opp then
						require('states.game'):new(me, opp)
						self.priv[nid] = nil
						me:hideCursor()
						closed = true
						return true
					end
				end
			elseif key == 'backspace' then
				if #id > 0 then
					id = id:sub(1, -2)
					me:send('\8 \8')
				end
			elseif key == 'ctrlc' then
				me:hideCursor()
				return me:setHandler(mainmenu)
			elseif #key == 1 then
				local kb = key:byte()
				if kb >= 48 and kb <= 57 then
					me:send(key)
					id = id .. key
				end
			end
		end
	end

	friendsmenu = telnet.genMenu('Play with a friend', {
		{label = 'Host a game', func = friends_host},
		{label = 'Enter an existing game', func = friends_enter},
		{label = 'Go back', func = function(me) return me:setHandler(mainmenu) end}
	})

	aboutmessage = function(me)
		me:fullClear()
		me:send('Tiny telnet battleship game written in Lua by igor725\r\n')
		me:send('Source code of this game released under MIT License\r\n')
		me:send('GitHub repository: https://github.com/igor725/telebattle\r\n')
		local motd = self.motd
		if #motd > 0 then
			me:text('\r\n^+bMOTD^-b:\r\n')
			for i = 1, #motd do
				me:text(motd[i] .. '\r\n')
			end
		end

		me:text('\r\n^+bPress any key to return to the main menu^-b')
		me:waitForInput()
		return me:setHandler(mainmenu)
	end

	local togglecolors = function(me)
		me:fullClear()
		if me:enableColors(not me:hasColors()) then
			if me:supportColors() then
				return me:setHandler(mainmenu)
			end

			me:putColor(32)
			me:send('If this text is green press Y, if not press N')
			me:putColor(0)

			while true do
				local key = me:waitForInput()

				if key == nil then
					return false
				elseif key == 'y' then
					return me:setHandler(mainmenu)
				elseif key == 'n' then
					me:enableColors(false)
					return me:setHandler(mainmenu)
				end
			end
		else
			return me:setHandler(mainmenu)
		end
	end

	mainmenu = telnet.genMenu('Welcome to the Telnet Battleship!', {
		{label = 'Search for game', func = function(me) return me:setHandler(searchstate) end},
		{label = 'Play with a friend', func = function(me) return me:setHandler(friendsmenu) end},
		{label = function(me)
			return 'Toggle ' ..
				(
					me:hasColors() and '\x1B[31mc\x1B[32mo\x1B[34ml\x1B[36mo\x1B[35mr\x1B[33ms\x1B[0m [X]'
					or 'colors [ ]'
				)
		end, func = togglecolors},
		{label = 'About', func = function(me) return me:setHandler(aboutmessage) end},
		{label = 'Exit', func = function(me) me:fullClear() me:send('Goodbye!\r\n') return false end}
	})

	tasker:newTask(function()
		local lastx

		while not closed do
			if tc:isBroken() then
				break
			end
			tc:send('\x1B[s')
			if lastx then
				tc:clearFromCur(lastx, 1)
			end

			local fmt = ocounter:getText()
			lastx = tc:getDimensions() - #fmt
			tc:textOn(lastx, 1, fmt)
			tc:send('\x1B[u')
			tasker.sleep(1)
		end

		tc:clearFromCur(lastx, 1)
	end)

	tc:hideCursor()
	tc:send('\x1B[=7l') -- Disable line wrap
	return tc:setHandler(mainmenu)
end

return _M
