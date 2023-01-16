local _H = {}
_H.__index = _H

function _H:getPos()
	return self.col, self.row
end

function _H:getField()
	return self.field
end

function _H:setPos(x, y)
	x, y = x or self.col or 0, y or self.row or 0
	if x < 0 or x > 9 or y < 0 or y > 9 then
		return
	end

	local tc = self.tc
	local field = self.field
	local ccol, crow = self.col, self.row

	if ccol and crow then
		local wx, wy = field:toWorld(ccol, crow)
		tc:textOn(wx, wy, field:getCharOn(ccol, crow, self.hide, tc:hasColors()))
	end

	local bx, by, rsx, rsy

	if ccol and crow then
		bx, by, rsx, rsy = field:border(ccol, crow)
		tc:textOn(bx, by, ' ') tc:textOn(rsx, rsy, ' ')
	end

	bx, by, rsx, rsy = field:border(x, y)
	tc:textOn(bx, by, '^') tc:textOn(rsx, rsy, '<')
	self.col, self.row = x, y

	if x and y then
		local wx, wy = field:toWorld(x, y)
		tc:textOn(wx, wy, '*')
	end
end

function _H:movedir(dc, dr)
	self:setPos(
		(self.col or 0) + dc,
		(self.row or 0) + dr
	)
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
		self:setPos(nil, nil)
		return false
	end

	self:setPos(nil, nil)
	return true
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

	if chb > 47 and chb < 58 then
		self:setPos(nil, chb - 48)
	elseif chb > 64 and chb < 75 then
		self:setPos(chb - 65, nil)
	elseif chb > 96 and chb < 107 then
		self:setPos(chb - 97, nil)
	else
		self:setPos(nil, nil)
		return false
	end

	return true
end

function _H:new(tc, field, hide)
	return setmetatable({
		tc = tc,
		field = field,
		row = 0, col = 0,
		hide = hide == true
	}, self)
end

return _H
