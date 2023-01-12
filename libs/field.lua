local _F = {}
_F.__index = _F

local header = '  A B C D E F G H I J'
local line = ' +-+-+-+-+-+-+-+-+-+-+'
local colors = {
	['-'] = '\x1B[35m-\x1B[0m',
	['X'] = '\x1B[31mX\x1B[0m',
	['#'] = '\x1B[34m#\x1B[0m'
}

function _F:draw(tc, dontmove, hits)
	local xpos = dontmove and 1 or (self:getPos() + 1)
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

function _F.getDimensions()
	return #line, (10 * 2) + 2
end

function _F:toWorld(x, y)
	return
		self:getPos() + (x * 2) + 3,
		(y * 2) + 3
end

function _F:getPos()
	return self.index * 32
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
		index = idx,
		matrix = {}
	}, self):configure()
end

return _F
