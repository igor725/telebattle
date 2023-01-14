local succ, lib = pcall(require, 'socket.core')

if not succ then
	if not jit then
		print('Failed to initialize socket library')
		return os.exit(1)
	end

	local ljsocket = require('libs.thirdparty.ljsocket')
	local ffi = require('ffi')
	local C = ffi.C

	if jit.os == 'Windows' then
		ffi.cdef[[
			typedef union _ULARGE_INTEGER {
				struct {
					unsigned long low;
					unsigned long high;
				} u;
				unsigned long long quad;
			} ULARGE_INTEGER;

			void Sleep(unsigned long ms);
			void GetSystemTimeAsFileTime(ULARGE_INTEGER *);
		]]

		sleep = function(ms)C.Sleep(math.floor(ms * 1000))end
		local lit = ffi.typeof('ULARGE_INTEGER[1]')
		gettime = function()
			local li = ffi.new(lit)
			C.GetSystemTimeAsFileTime(li[0])
			local time = tonumber(li[0].u.low) / 1.0e7 +
				tonumber(li[0].u.high) * (4294967296.0 / 1.0e7)
			return (time - 11644473600.0)
		end
	else
		ffi.cdef[[
			struct timeval {
				long tv_sec;
				long tv_usec;
			};

			void usleep(unsigned int us);
			int gettimeofday(struct timeval *, void *);
		]]

		sleep = function(ms)C.usleep(math.floor(ms * 1000000))end
		local tst = ffi.typeof('struct timeval[1]');
		gettime = function()
			local ts = ffi.new(tst)
			C.gettimeofday(ts, nil)
			return tonumber(ts[0].tv_sec) + tonumber(ts[0].tv_usec) / 1.0e6
		end
	end

	function initServer(ip, port)
		local info = ljsocket.find_first_address(ip, port)
		if not info then print('No adapter found') return 1 end
		local server = assert(ljsocket.create(info.family, info.socket_type, info.protocol))
		assert(server:set_blocking(false))
		assert(server:set_option('nodelay', true, 'tcp'))
		assert(server:set_option('reuseaddr', true))
		assert(server:bind(info))
		assert(server:listen())
		return server, info:get_ip(), info:get_port()
	end

	function acceptClient(fd)
		local cl, err = fd:accept()
		if cl then
			assert(cl:set_blocking(false))
			assert(fd:set_option('nodelay', true, 'tcp'))
			return cl
		end

		return cl, err
	end
else
	function initServer(ip, port)
		if ip == '*' then
			ip = '0.0.0.0'
		end

		local server = lib.tcp()
		assert(server:settimeout(0))
		assert(server:setoption('reuseaddr', true))
		assert(server:setoption('tcp-nodelay', true))
		assert(server:bind(ip, port))
		assert(server:listen())
		return server, server:getsockname()
	end

	function acceptClient(fd)
		local cl, err = fd:accept()
		if cl then
			assert(cl:settimeout(0))
			assert(cl:setoption('tcp-nodelay', true))
			return cl
		end

		return cl, err
	end

	gettime = lib.gettime
	sleep = lib.sleep
end
