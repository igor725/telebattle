local ffi = require('ffi')
local sleep, gettime
local C = ffi.C

if jit.os == 'Windows' then
	ffi.cdef[[
		typedef union _ULARGE_INTEGER {
			struct {
				unsigned long low;
				unsigned long high;
			} u;
			unsigned long long quad;
		} LARGE_INTEGER;

		void Sleep(unsigned long ms);
		void GetSystemTimeAsFileTime(LARGE_INTEGER *);
	]]
	sleep = function(ms)C.Sleep(ms)end
	local lit = ffi.typeof('LARGE_INTEGER[1]')
	gettime = function()
		local li = ffi.new(lit)
		C.GetSystemTimeAsFileTime(li[0])
		return li[0].quad / 10000ULL
	end
else
	ffi.cdef[[
		struct timespec {
			long tv_sec;
			long tv_usec;
		};

		void usleep(unsigned int us);
		int clock_gettime(int, struct timespec *);
	]]

	sleep = function(ms)C.usleep(1000 * ms)end
	local tst = ffi.typeof('struct timespec[1]');
	gettime = function()
		local ts = ffi.new(tst)
		C.clock_gettime(0, ts)
		return ts[0].tv_sec * 1000 + ts[0].tv_usec / 1000;
	end
end

local _T = {
	list = {},
	onerror = {}
}

function _T.sleep(sec)
	local time = gettime() + sec
	while gettime() < time do
		coroutine.yield()
	end
end

function _T:newTask(func, errh)
	local coro = coroutine.create(function()
		func() return true
	end)
	table.insert(self.list, coro)
	self.onerror[coro] = errh
end

function _T:update()
	local coros = self.list
	for i = #coros, 1, -1 do
		local coro = coros[i]
		local ret, st = coroutine.resume(coro)
		if ret == false or st == true then
			table.remove(coros, i)
			if ret == false then
				print('coro error', coro, st)
				local errh = self.onerror[coro]
				if errh then pcall(errh, st)end
			end
		end
	end
end

function _T:runLoop()
	while true do
		self:update()
		sleep(16)
	end
end

return _T
