local _H = {}
_H.__index = _H

function _H:getPos()
	return self.col, self.row
end

function _H:getField()
	return self.field
end

function _H:setRowHint(p)
	if p < 0 or p > 9 then
		return
	end
	local tc = self.tc
	local off = self.field:getDimensions()
	off = off + self.offset + 1

	if self.row then
		tc:textOn(off, 3 + (self.row * 2), ' ')
	end
	tc:textOn(off, 3 + (p * 2), '<')
	self.row = p
end

function _H:setColHint(p)
	if p < 0 or p > 9 then
		return
	end
	local tc = self.tc
	local ccol = self.col
	if ccol then
		tc:textOn(self.offset + 3 + (ccol * 2), 23, ' ')
	end
	tc:textOn(self.offset + 3 + (p * 2), 23, '^')
	self.col = p
end

function _H:place(char)
	local col = self.col
	local row = self.row
	local tc = self.tc

	if col and row then
		tc:textOn(
			self.offset + 3 + (col * 2), 3 + (row * 2),
			char or self.field:getCharOn(col, row, self.hide, tc:hasColors())
		)
	end
end

function _H:handleKey(key)
	if key == 'aleft' then
		self:movedir(-1, 0)
	elseif key == 'aright' then
		self:movedir(1, 0)
	elseif key == 'aup' then
		self:movedir(0, -1)
	elseif key == 'adown' then
		self:movedir(0, 1)
	else
		return false
	end

	return true
end

function _H:movedir(dc, dr)
	self.col = self.col or 0
	self.row = self.row or 0
	self:place(nil)
	self:setColHint(self.col + dc)
	self:setRowHint(self.row + dr)
	self:place('*')
end

function _H:update(ch)
	if type(ch) ~= 'string' then
		return false
	elseif self:handleKey(ch) then
		return true
	elseif #ch > 1 then
		return false
	end

	local chb = ch:byte()

	self:place(nil)
	if chb > 47 and chb < 58 then
		self:setRowHint(chb - 48)
	elseif chb > 64 and chb < 75 then
		self:setColHint(chb - 65)
	elseif chb > 96 and chb < 107 then
		self:setColHint(chb - 97)
	else
		self:place('*')
		return false
	end

	self:place('*')
	return true
end

function _H:new(tc, field, hide, dontmove)
	return setmetatable({
		hide = hide == true,
		offset = dontmove and 0 or field:getPos(),
		field = field,
		tc = tc,
		row = 0,
		col = 0
	}, self)
end

return _H
