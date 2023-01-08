local _Ga = {}
_Ga.__index = _Ga

local helptext = {
	'Arrows - field cursor navigation',
	'Tab - change the ship type',
	'Enter - place the selected ship',
	'M - remove the ship under the cursor',
	'R - rotate the ship under the cursor',
	'P - randomize ships',
	'Z - clear the field',
	'S - start the game',
	'',
	'You can also move the cursor around the',
	'field by pressing the buttons A-J and 0-9',
	'',
	'Once you finish, press Enter again',
	'to start the game'
}

function _Ga:fieldOf(pl)
	return self.fields[pl]
end

function _Ga:finish(w)
	self.active = false
	self.winner = self.winner or w
end

function _Ga:playerReady()
	self.state = self.state + 1
	if self.turn == nil then
		self.turn = self.players[math.random(1, 2)]
	end
end

function _Ga:waitStart(tc)
	while self.active and self.state < 2 do
		if tc:isBroken() then
			return false
		end
		coroutine.yield()
	end

	return self.active
end

function _Ga:waitTurn(tc)
	while self.active and self.turn ~= tc do
		if tc:isBroken() then
			return false
		end
		coroutine.yield()
	end

	return self.active
end

function _Ga:configure()
	local wait = tasker:newWaitable()
	local function makemessage(text)
		return function(me)
			me:fullClear()
			me:send(text .. '\r\nPress any key to return to the main menu')
			me:read(1)
			menu:run(me)
			return true
		end
	end

	local function game(me)
		local myfield = self:fieldOf(me)
		local w, h = myfield:getDimensions()
		local status = h + 4
		local title = h + 2
		local _hint, opp

		me:fullClear()
		me:send('Waiting for opponent to finish placing ships...')
		if not self:waitStart(me) then
			me:setHandler(makemessage('Game canceled'))
			return true
		end

		me:fullClear()
		for owner, field in pairs(self.fields) do
			local hide = owner ~= me
			local xpos = field:getPos()
			local text
			field:draw(me, false, hide)
			if hide then
				opp = owner
				text = 'Opponent\'s field'
				_hint = hint:new(me, field, true)
			else
				text = 'Your field'
			end
			me:textOn(xpos + (w - #text) / 2, title, text)
		end

		while self.active do
			me:textOn(1, status, 'Opponent\'s turn')
			if not self:waitTurn(me) then
				break
			end
			me:textOn(1, status, 'Your turn!')
			me:clearFromCur()
			while self.turn == me do
				local char = me:read(1, wait)
				if not char then
					self:finish()
					break
				end
				if not _hint:update(char, false, wait) then
					if char == '\r' then
						local field = _hint:getField()
						local x, y = _hint:getPos()
						if field:hit(x, y) then
							local wx, wy = field:toWorld(x, y)
							me:textOn(wx, wy, field:getCharOn(x, y, true))
							opp:textOn(wx, wy, field:getCharOn(x, y, true))

							if field:isAlive() then
								if not field:isKilled(x, y) then
									self.turn = opp
								end
							else
								self:finish(me)
								me:setHandler(makemessage('You win!'))
								opp:setHandler(makemessage('You loose!'))
							end
						end
					end
				end
			end
		end

		wait:signal()
		if self.winner == nil then
			me:setHandler(makemessage('Opponent left the game'))
		end

		return true
	end

	local function placing(me)
		local myfield = self:fieldOf(me)
		local _placer = placer:new(myfield)
		local w = myfield:getDimensions()
		me:fullClear()
		myfield:draw(me, true)
		local _hint = hint:new(me, myfield)
		local shoff = w + 4
		local marker = shoff + 12
		local selected = 0

		local function updateShipSelection(new)
			me:textOn(marker, 2 + selected, ' ')
			me:textOn(marker, 2 + new, '*')
			selected = new
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

		me:textOn(shoff, 1, 'Press tab to select ship to place')
		updateShipSelection(0)
		updateShipInfo()

		for i = 1, #helptext do
			local text = helptext[i]
			if #text > 0 then
				me:textOn(shoff, 6 + i, text)
			end
		end

		while self.active do
			local char = me:read(1, wait)
			if not char then break end
			if not _hint:update(char, true, wait) then
				local x, y = _hint:getPos()
				if char == '\r' then -- Return
					if _placer:isReady() then
						me:setHandler(game)
						self:playerReady()
						return true
					else
						if _placer:place(x, y, selected) then
							updateShipInfo(selected)
							myfield:draw(me, true)
						end
					end
				elseif char == '\t' then -- tab
					updateShipSelection((selected + 1) % 4)
				elseif char == 'r' then
					if _placer:rotate(x, y) then
						myfield:draw(me, true)
					end
				elseif char == 'z' then
					if _placer:removeAll() then
						myfield:draw(me, true)
						updateShipInfo()
					end
				elseif char == 'p' then
					_placer:randomPlace()
					myfield:draw(me, true)
					updateShipInfo()
				elseif char == 'm' then
					local sh, id = _placer:getShipOn(x, y)
					if id ~= nil then
						if _placer:remove(id) then
							local sht = sh:getType()
							updateShipInfo(sht)
							updateShipSelection(sht)
							myfield:draw(me, true)
							_hint:update('\0', true)
						end
					end
				end
			end

			coroutine.yield()
		end

		me:setHandler(makemessage('Opponent left the game'))
		return true
	end

	for i = 1, 2 do
		self.players[i]:setHandler(placing)
	end

	self.configure = false
	return self
end

function _Ga:new(p1, p2)
	return setmetatable({
		players = {p1, p2},
		active = true,
		turn = nil,
		state = 0,
		fields = {
			[p1] = field:new(0),
			[p2] = field:new(1)
		},
	}, self):configure()
end

return _Ga
