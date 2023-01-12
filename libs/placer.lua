local _P = {}
_P.__index = _P

local ship_mt = {
	getDirection = function(self)
		local dir = self.dir
		return
			dir == 0 and 1 or 0,
			dir == 1 and 1 or 0
	end,
	getPos = function(self)
		return self.x, self.y
	end,
	getLength = function(self)
		return self.len
	end,
	getType = function(self)
		return self.len - 1
	end,

	collidedWith = function(self, x, y)
		local dx, dy = self:getDirection()
		local sx, sy = self:getPos()
		local len = self:getLength()

		return x >= sx and x <= sx + len * dx - (dx * 1) and
		y >= sy and y <= sy + len * dy - (dy * 1)
	end,

	attack = function(self)
		if self.health < 1 then return true end
		self.health = self.health - 1
		return self.health < 1
	end
}
ship_mt.__index = ship_mt

local function newShip(x, y, dir, len)
	return setmetatable({
		dir = dir, len = len,
		health = len,
		x = x, y = y,
	}, ship_mt)
end

function _P:getShipOn(x, y)
	local placed = self.placed

	for i = 1, #placed do
		if placed[i]:collidedWith(x, y) then
			return placed[i], i
		end
	end

	return nil, nil
end

function _P:testSpace(x, y, t, dir, ignid)
	local ex = dir == 0 and (x + t) or x
	local ey = dir == 0 and y or (y + t)
	if ex > 9 or ey > 9 then return false end
	local field = self.field

	for i = math.max(0, y - 1), math.min(9, ey + 1) do
		for j = math.max(0, x - 1), math.min(9, ex + 1) do
			if field:getCharOn(j, i, false) ~= ' ' then
				if ignid == nil or select(2, self:getShipOn(j, i)) ~= ignid then
					return false
				end
			end
		end
	end

	return true
end

function _P:place(x, y, t, d)
	local avail = self.avail
	if avail[t] < 1 then
		return false
	end

	local len = (t + 1)
	local dir
	if d == nil then
		for i = 0, 1 do
			if self:testSpace(x, y, t, i) then
				dir = i
				break
			end
		end
		if dir == nil then
			return false
		end
	else
		dir = d == 0 and 0 or 1
	end

	local field = self.field
	for i = 0, t do
		field:setCharOn(
			dir == 0 and x + i or x,
			dir == 0 and y or y + i,
			'#'
		)
	end

	table.insert(self.placed, newShip(x, y, dir, len))
	avail[t] = avail[t] - 1

	return true
end

function _P:randomPlace()
	self:removeAll()
	local cnt = 0

	for i = 0, 3 do
		while not self:place(
			math.random(0, 9),
			math.random(0, 9),
			i, nil
		) or self:getAvail(i) > 0 do
			cnt = cnt + 1
			if cnt > 5000 then
				self:randomPlace()
				break
			end
		end
	end
end

function _P:removeAll()
	local placed = self.placed
	if #placed < 1 then return false end

	for i = #placed, 1, -1 do
		self:remove(i)
	end

	return true
end

function _P:remove(id)
	id = tonumber(id)
	if not id then return false end
	local sh = table.remove(self.placed, id)
	if sh == nil then return false end
	local field = self.field
	local avail = self.avail
	local t = sh:getType()
	avail[t] = avail[t] + 1

	local dx, dy = sh:getDirection()
	for i = 0, t do
		field:setCharOn(
			sh.x + i * dx,
			sh.y + i * dy,
			' '
		)
	end

	return true
end

function _P:rotate(x, y)
	local sh, id = self:getShipOn(x, y)
	if sh == nil then return false end

	local newdir = sh.dir == 0 and 1 or 0
	local sx, sy = sh:getPos()
	local shtype = sh:getType()
	if self:testSpace(sx, sy, shtype, newdir, id) then
		return self:remove(id) and self:place(sx, sy, shtype, newdir)
	end

	return false
end

function _P:getAvail(i)
	return self.avail[i]
end

function _P:isReady()
	local avail = self.avail
	for i = 0, 3 do
		if avail[i] > 0 then
			return false
		end
	end

	return true
end

function _P:new(field)
	return setmetatable({
		avail = {[0] = 4, 3, 2, 1},
		placed = {},
		field = field
	}, self)
end

return _P
