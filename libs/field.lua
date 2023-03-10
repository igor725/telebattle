local _F = {}
_F.__index = _F

local header = '  A B C D E F G H I J'
local line = ' +-+-+-+-+-+-+-+-+-+-+'
local colors = {
	['-'] = '\x1B[35m-\x1B[0m',
	['X'] = '\x1B[31mX\x1B[0m',
	['#'] = '\x1B[34m#\x1B[0m'
}

function _F:setRelativeDrawing(state)
	self.reldraw = state
end

function _F:draw(tc, hits)
	local xpos = 1 + self:getPos()
	tc:textOn(xpos, 1, header)
	tc:textOn(xpos, 2, line)

	for i = 0, 9 do
		local y = 3 + (i * 2)
		tc:textOn(xpos, y, string.char(48 + i) .. '|')
		for j = 0, 9 do
			tc:send(('%s|'):format(
				self:getCharOn(j, i, hits, tc:hasColors())
			))
		end
		tc:textOn(xpos, y + 1, line)
	end
end

function _F:hit(x, y)
	local mx = self.matrix[y][x]
	if mx[2] then return false end
	mx[2] = true
	return true
end

function _F:isHit(x, y)
	return self.matrix[y][x][2]
end

function _F:isAlive()
	local mat = self.matrix
	for i = 0, 9 do
		local row = mat[i]
		for j = 0, 9 do
			local col = row[j]
			if col[1] ~= ' ' and col[2] == false then
				return true
			end
		end
	end

	return false
end

function _F:setCharOn(x, y, c)
	self.matrix[y][x][1] = c
end

function _F:getCharOn(x, y, hit, clr)
	local mat = self.matrix[y][x]
	local cval = mat[1]
	if not hit then return (clr and colors[cval]) or cval end
	local char = (mat[2] and (cval ~= ' ' and 'X' or '-')) or ' '
	if clr then return colors[char] or char end
	return char
end

function _F:getDimensions()
	return #line, (10 * 2) + 2
end

function _F:toWorld(x, y)
	return
		self:getPos() + (x * 2) + 3,
		(y * 2) + 3
end

function _F:border(x, y)
	local dx, dy = self:getDimensions()
	local bx, by, rsx, rsy = 1, dy, dx, 1
	dx, dy = dx + 1, dy + 1

	if y <= dy then
		rsx, rsy = self:getPos() + dx, 3 + (y * 2)
	end

	if x <= dx then
		bx, by = self:getPos() + 3 + (x * 2), dy
	end

	return bx, by, rsx, rsy
end

function _F:getPos()
	return self.reldraw and 0 or self.index * 32
end

function _F:reset()
	local m = self.matrix
	for i = 0, 9 do
		local r = m[i]
		for j = 0, 9 do
			local c = r[j]
			c[1], c[2] = ' ', false
		end
	end
end

function _F:configure()
	local f = self.matrix
	for i = 0, 9 do
		local t = {}
		for j = 0, 9 do
			t[j] = {' ', false}
		end
		f[i] = t
	end

	self.configure = false
	return self
end

function _F:new(idx)
	return setmetatable({
		reldraw = false,
		index = idx,
		matrix = {}
	}, self):configure()
end

return _F
