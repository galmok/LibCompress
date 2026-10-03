--[[
Stage 2 of the backwards compatibility check: decodes what cross-new.lua wrote with an
older copy of the library.

Get the older copy from history; for revisions before r87 the $Revision$ keyword is not
expanded in git, so replace that line with the version it had at the time:

	git show ce943d2:LibCompress.lua > old.lua   (then patch the NewLibrary line)
	OLDLIB=old.lua LIBSTUB=../Libs/LibStub/LibStub.lua RECORDS=cap1.bin lua cross-old.lua
]]

-- Decodes the streams written by cross-new.lua with an older library, to prove that the
-- capability 1 default really is decodable by peers that have not upgraded.

dofile("shim.lua")
dofile(os.getenv("LIBSTUB"))
dofile(os.getenv("OLDLIB"))

local old = LibStub:GetLibrary("LibCompress", true)
print(("old library under test: %s"):format(tostring(LibStub.minors["LibCompress"])))

local f = assert(io.open(os.getenv("RECORDS"), "rb"))
local content = f:read("a")
f:close()

local i, cases, passed, failed = 1, 0, 0, 0
while i <= #content do
	local streamLen
	streamLen, i = string.unpack(">I4", content, i)
	local stream = content:sub(i, i + streamLen - 1)
	i = i + streamLen
	local rawLen
	rawLen, i = string.unpack(">I4", content, i)
	local original = content:sub(i, i + rawLen - 1)
	i = i + rawLen

	cases = cases + 1
	local ok, result = pcall(function() return old:Decompress(stream) end)
	if ok and result == original then
		passed = passed + 1
	else
		failed = failed + 1
		print(("  FAIL case %d: header %d, %d bytes -> %s")
			:format(cases, stream:byte(1), #stream, ok and tostring(result and #result or result) or result))
	end
end

print(("old library decoded %d/%d streams"):format(passed, cases))
if failed > 0 then
	os.exit(1)
end
