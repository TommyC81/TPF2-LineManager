-- From VacuumTube, link: https://www.transportfever.net/index.php?thread/18137-game-script-api-res-constructionrep-getall/&pageNo=1
local t = {}

function t.timestamp(ts)
	return {
		clock = os.clock(),
		date = os.date("%Y-%m-%d  %H:%M:%S", ts and (os.time() - os.clock() + ts)),
	}
end

local st = 0
local rnd = 0

function t.start()
	local now = os.clock()
	rnd = now
	st = now
	return now
end

function t.get()
	return os.clock() - st
end

function t.round()
	local now = os.clock()
	local ret = now - rnd
	rnd = now
	return ret
end

function t.stop()
	local ret = t.get()
	t.reset()
	return ret
end

function t.reset()
	st = 0
	rnd = 0
end

function t.timefunc(f, n, ...)
	t.start()
	for i = 1, (n or 1) do
		f(...)
	end
	print("Total Time for " .. (n or 1) .. "x: " .. t.stop() .. " s")
end

return t
