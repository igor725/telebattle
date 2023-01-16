local _Ga = {}
_Ga.__index = _Ga

local field = require('libs.field')
local hint = require('libs.hint')
local placer = require('libs.placer')

local helptext = {
	'Arrows - field cursor navigation',
	'Tab - change the ship type',
	'Enter - place the selected ship / fire (ingame)',
	'M - remove the ship under the cursor',
	'R - rotate the ship under the cursor',
	'P - randomize ships',
	'Z - clear the field',
	'',
	'You can also move the cursor around the',
	'field by pressing the buttons A-J and 0-9',
	'',
	'Once you finish, press Enter again',
	'to start the game'
}

function _Ga:close()
	self.fields = nil
	self.placers = nil
	self.closed = true
	self.state = -1
end

function _Ga:fieldOf(pl)
	return self.fields[pl]
end

function _Ga:placerOf(fi)
	return self.placers[fi]
end

function _Ga:finish(w)
	self.active = false
	self.winner = self.winner or w
end

function _Ga:playerReady()
	self.state = self.state + 1
	if self.turn == nil then
		for _ = 0, math.random(0, 1) do
			self.turn = next(self.fields, self.turn)
		end
	end
end

function _Ga:waitStart(tc)
	while self.active and self.state < 2 do
		coroutine.yield()

		if tc:isBroken() then
			return false
		end
	end

	return self.active
end

function _Ga:waitTurn(tc)
	while self.active and self.turn ~= tc do
		coroutine.yield()

		if tc:isBroken() then
			return false
		end
	end

	return self.active
end

function _Ga:getOpponentOf(pl)
	if self.fields == nil then
		return -1
	end

	for opp in pairs(self.fields) do
		if opp ~= pl then return opp end
	end
end

function _Ga:configure()
	local gamestate, placingstate
	local signal = tasker:newSignal()
	local scores = {}

	local function makemessage(text)
		return function(me)
			me:fullClear()
			me:send(text .. '\r\nPress Enter to return to the main menu')
			while me:waitForInput() ~= 'enter' do end
			menu:run(me)
			self:close()
			return true
		end
	end

	local refused = makemessage('The opponent refused to play the next game')
	local endgame = telnet.genMenu(function(me)
		local opp = self:getOpponentOf(me)
		return (self.winner == me and 'You win!' or 'You loose!') ..
		('\r\nYou: %d, Opponent: %d'):format(scores[me] or 0, scores[opp] or 0)
	end, {
		{
			label = 'Play another game with this player',
			func = function(me)
				if self.state == -1 then
					return me:setHandler(refused)
				elseif self.state == 4 then -- Новая игра уже запрошена вторым игроком
					self.state = 5
					return me:setHandler(function()
						while self.state == 5 do
							coroutine.yield()

							if me:isBroken() then
								self:close()
								return false
							end
						end

						if self.state == -1 then
							return me:setHandler(refused)
						end

						local _field = self:fieldOf(me)
						_field:reset()
						self:placerOf(_field):removeAll()
						return me:setHandler(placingstate)
					end)
				elseif self.state == 3 then -- Новая игра ещё не была запрошена
					self.turn, self.state, self.active = nil, 4, true
					return me:setHandler(function()
						me:fullClear()
						me:send('Waiting for other player....')
						while self.state == 4 do
							coroutine.yield()

							if me:isBroken() then
								self:close()
								return false
							end
						end

						if self.state == -1 then
							return me:setHandler(refused)
						end

						self.state = 0
						local _field = self:fieldOf(me)
						_field:reset()
						self:placerOf(_field):removeAll()
						return me:setHandler(placingstate)
					end)
				end
			end
		},
		{
			label = 'Exit to main menu',
			func = function(me)
				self:close()
				return menu:run(me)
			end
		}
	})

	gamestate = function(me)
		local w, h = self:fieldOf(me):getDimensions()
		local alivex = w + 36
		local yoursx = alivex + 10
		local oppsx = alivex + 20
		local status = h + 4
		local title = h + 2
		local _hint, opp

		me:fullClear()
		me:send('Waiting for opponent to finish placing ships...')
		if not self:waitStart(me) then
			me:setHandler(makemessage('Game canceled'))
			self:close()
			return true
		end

		me:fullClear() me:send('\a')
		for owner, field in pairs(self.fields) do
			local hide = owner ~= me
			local xpos = field:getPos()
			local text
			field:setRelativeDrawing(false)
			field:draw(me, hide)
			owner:textOn(alivex, 1, 'Ships | Yours | Opponent\'s')
			for i = 0, 3 do
				owner:textOn(alivex, 2 + i, ('%+5s |   %d   |     %d'):format(
					('#'):rep(i + 1), 4 - i, 4 - i
				))
			end

			if hide then
				opp = owner
				text = 'Opponent\'s field'
				_hint = hint:new(me, field, true)
			else
				text = 'Your field'
			end
			me:textOn(xpos + (w - #text) / 2, title, text)
		end
		me:textOn(alivex, 7, ('Your score: %d'):format(scores[me] or 0))
		me:textOn(alivex, 8, ('Opponent\'s score: %d'):format(scores[opp] or 0))

		self.lttime = gettime()
		while self.active do
			signal:reset()
			me:textOn(1, status, 'Opponent\'s turn')
			if not self:waitTurn(me) then
				self:finish()
				break
			end
			me:textOn(1, status, 'Your turn!\a')
			me:clearFromCur()
			while self.turn == me do
				local key, err = me:waitForInput(signal)
				if key == nil then
					if err == 'signaled' then
						break
					elseif err == 'closed' then
						self:finish()
						return false
					end
				end

				if not _hint:update(key) then
					if key == 'enter' then
						local _field = _hint:getField()
						local _placer = self:placerOf(_field)
						local x, y = _hint:getPos()

						if _field:hit(x, y) then
							if _field:isAlive() then
								self.lttime = gettime()
								local wx, wy = _field:toWorld(x, y)
								me:textOn(wx, wy, _field:getCharOn(x, y, true, me:hasColors()))
								opp:textOn(wx, wy, _field:getCharOn(x, y, true, opp:hasColors()))

								local ship = _placer:getShipOn(x, y)
								if not ship then
									self.turn = opp
								else
									if ship:attack() then
										local type = ship:getType()
										local ypos = 2 + type
										local avail = _placer:aliveCount(type)
										opp:textOn(yoursx, ypos, avail)
										me:textOn(oppsx, ypos, avail)

										local len = ship:getLength()
										local sx, sy = ship:getPos()
										local dx, dy = ship:getDirection()
										for i = math.max(0, sy - 1), math.min(9, sy + (len * dy) + (1 * dx)) do
											for j = math.max(0, sx - 1), math.min(9, sx + (len * dx) + (1 * dy)) do
												if _field:hit(j, i) then
													local nwx, nwy = _field:toWorld(j, i)
													me:textOn(nwx, nwy, _field:getCharOn(j, i, true, me:hasColors()))
													opp:textOn(nwx, nwy, _field:getCharOn(j, i, true, opp:hasColors()))
												end
											end
										end
									end
								end
							else
								scores[me] = (scores[me] or 0) + 1
								self:finish(me)
								me:setHandler(endgame)
								opp:setHandler(endgame)
								self.state = 3
								break
							end
						end
					elseif key == 'ctrlc' then
						self:finish(opp)
					end
				end
			end
		end

		if self.winner == nil then
			me:setHandler(makemessage('Opponent left the game'))
			signal:signal()
			self:close()
		end

		return true
	end

	placingstate = function(me)
		local _field = self:fieldOf(me)
		_field:setRelativeDrawing(true)
		local _placer = self:placerOf(_field)
		local _hint = hint:new(me, _field, false)
		local w = _field:getDimensions()
		me:fullClear()
		_field:draw(me, false)
		local shoff = w + 4
		local marker = shoff + 12
		local selected = 0

		local function updateShipSelection(new)
			me:textOn(marker, 2 + selected, ' ')
			me:textOn(marker, 2 + new, '*')
			selected = new
		end

		local function selectNext()
			updateShipSelection((selected + 1) % 4)
		end

		local function updateShipInfo(ty)
			if ty then
				local len = ty + 1
				me:textOn(shoff, 2 + ty,
					('%d. %+4s (%d)'):format(len, ('#'):rep(len), _placer:getAvail(ty))
				)
			else
				for i = 0, 3 do
					updateShipInfo(i)
				end
			end
		end

		me:textOn(shoff, 1, 'Available ships:')
		updateShipSelection(0)
		updateShipInfo()

		for i = 1, #helptext do
			local text = helptext[i]
			if #text > 0 then
				me:textOn(shoff, 6 + i, text)
			end
		end

		while self.active do
			local key, err = me:waitForInput(signal)

			if key == nil then
				self:finish()
				if err == 'closed' then
					signal:signal()
					return false
				elseif err == 'signaled' then
					break
				end
			end

			local x, y = _hint:getPos()

			if not _hint:update(key) then
				if key == 'r' then
					if _placer:rotate(x, y) then
						_field:draw(me, false)
					end
				elseif key == 'z' then
					if _placer:removeAll() then
						_field:draw(me, false)
						updateShipInfo()
					end
				elseif key == 'p' then
					_placer:randomPlace()
					_field:draw(me, false)
					updateShipInfo()
				elseif key == 'm' then
					local sh, id = _placer:getShipOn(x, y)
					if id ~= nil then
						if _placer:remove(id) then
							local sht = sh:getType()
							updateShipInfo(sht)
							updateShipSelection(sht)
							_field:draw(me, false)
							_hint:update('\0')
						end
					end
				elseif key == 'tab' then
					selectNext()
				elseif key == 'ctrlc' then
					self:finish()
					menu:run(me)
					return true
				elseif key == 'enter' then
					if _placer:isReady() then
						self:playerReady()
						return me:setHandler(gamestate)
					else
						if _placer:place(x, y, selected) then
							updateShipInfo(selected)
							_field:draw(me, false)
							if _placer:getAvail(selected) < 1 then
								selectNext()
							end
						end
					end
				end
			end

			coroutine.yield()
		end

		me:setHandler(makemessage('Opponent left the game'))
		signal:signal()
		self:close()
		return true
	end

	for pl, fl in pairs(self.fields) do
		self.placers[fl] = placer:new(fl)
		pl:setHandler(placingstate)
	end

	tasker:newTask(function()
		local lturn, nextbell
		local tdiff, skips = 0, 0
		-- local pltimeout = 300
		local timeout = 30

		while not self.closed do
			if self.state == 2 then
				if lturn ~= self.turn then
					lturn = self.turn
					nextbell = timeout - 5
					if tdiff >= timeout then
						skips = skips + 1
						if skips == 4 then
							signal:signal()
							self:finish()
						end
					else
						skips = 0
					end
				else
					tdiff = gettime() - self.lttime
					if tdiff >= timeout then
						signal:signal()
						self.turn = self:getOpponentOf(lturn)
						self.lttime = gettime()
					elseif tdiff >= nextbell then
						nextbell = nextbell + 1
						lturn:send('\a')
					end
				end
			end

			coroutine.yield()
		end
	end)

	self.configure = false
	return self
end

function _Ga:new(p1, p2)
	return setmetatable({
		active = true,
		closed = false,
		turn = nil,
		state = 0,
		placers = {},
		fields = {
			[p1] = field:new(0),
			[p2] = field:new(1)
		},
	}, self):configure()
end

return _Ga
