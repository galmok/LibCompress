--[[
Stage 1 of the backwards compatibility check: writes streams produced by the current
library so that an older library can decode them in a separate process.

	LIBSTUB=../Libs/LibStub/LibStub.lua NEWLIB=../LibCompress.lua RECORDS=cap1.bin lua cross-new.lua
	CAPABILITY=2 FILTER=sub ... RECORDS=cap2.bin lua cross-new.lua

Stage 2 is cross-old.lua. Capability 1 streams must decode, capability 2 ones must not -
that second result is what proves the check is not passing vacuously.
]]

-- Writes capability-1 streams produced by the current library, for the old library to
-- decode in a separate process.

dofile("shim.lua")
dofile(os.getenv("LIBSTUB"))
dofile(os.getenv("NEWLIB"))

local LibCompress = LibStub:GetLibrary("LibCompress", true)
local capability = (os.getenv("CAPABILITY") == "2") and 2 or nil
local filter = os.getenv("FILTER")

local function allBytes()
	local t = {}
	for i = 0, 255 do t[#t + 1] = string.char(i) end
	return table.concat(t)
end

local payloads = {
	empty = "",
	one = "x",
	allbytes = allBytes(),
	text = string.rep("plain ascii text with spaces and dots.\n", 20),
	flat = string.rep("\000", 3000),
	gradient = (function()
		local t = {}
		for i = 0, 2999 do t[#t + 1] = string.char(i % 256) end
		return table.concat(t)
	end)(),
	noise = (function()
		local t, seed = {}, 12345
		for i = 1, 3000 do
			seed = (seed * 1103515245 + 12345) % 2147483648
			t[i] = string.char(seed % 256)
		end
		return table.concat(t)
	end)(),
	unicode = string.rep("a\228\154\131\240\159\152\131", 50),
}

local out = assert(io.open(os.getenv("RECORDS"), "wb"))
local count = 0
for name, data in pairs(payloads) do
	local stream = LibCompress:Compress(data, capability, filter)
	assert(type(stream) == "string", name .. " did not compress")
	out:write(string.pack(">I4", #stream), stream)
	out:write(string.pack(">I4", #data), data)
	count = count + 1
end
out:close()
print(("wrote %d capability-%s streams (library %s)"):format(count, tostring(capability or 1), tostring(LibStub.minors["LibCompress"])))
