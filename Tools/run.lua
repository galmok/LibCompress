--[[
Runs the repository test driver under plain Lua. There is no C_EncodingUtil here, so
only the pure Lua codecs are exercised; the in game /lctest run covers the zlib family.

	LIBSTUB=../Libs/LibStub/LibStub.lua LIBCOMPRESS=../LibCompress.lua 		DRIVER=../LibCompressTest/LibCompressTest.lua lua run.lua
]]

local libPath = assert(os.getenv("LIBCOMPRESS"), "set LIBCOMPRESS to LibCompress.lua")
local driverPath = assert(os.getenv("DRIVER"), "set DRIVER to LibCompressTest.lua")

dofile("shim.lua")

local libStubPath = assert(os.getenv("LIBSTUB"), "set LIBSTUB to LibStub.lua")
dofile(libStubPath)

dofile(libPath)
assert(LibStub and LibStub:GetLibrary("LibCompress", true), "library did not register")

dofile(driverPath)
SlashCmdList.LIBCOMPRESSTEST("")
SlashCmdList.LIBCOMPRESSTEST("copy")
print("report window built")
