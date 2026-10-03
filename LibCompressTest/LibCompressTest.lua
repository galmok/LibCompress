--[[
Test driver for LibCompress (deflate/zlib/gzip, prefilters, checksum helpers, logged
encode table). It lives in the LibCompress repository and is left out of the packaged
file; point an AddOns folder at this directory to run it against the library next to it.

	/lctest			run everything, print the summary
	/lctest copy	copy the last report to the clipboard
]]--

local EXPECTED_MINOR = 90087

local LibCompressTest = {}
local LibCompress
local passed, failed, report

local function log(text)
	report[#report + 1] = text
	print(text)
end

local function check(name, ok, detail)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		log(("  FAIL  %s%s"):format(name, detail and ("  <" .. tostring(detail) .. ">") or ""))
	end
end

--------------------------------------------------------------------------------
-- payloads

local function allBytes()
	local t = {}
	for i = 0, 255 do
		t[#t + 1] = string.char(i)
	end
	return table.concat(t)
end

local function buildPayloads()
	local gradient = {}
	for i = 0, 999 do
		local v = (i * 7) % 256
		gradient[#gradient + 1] = string.char(v, v, v)
	end

	-- deterministic noise, so the size report can be compared across runs
	local seed = 1
	local function rnd()
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local noise = {}
	for i = 1, 3000 do
		noise[#noise + 1] = string.char(math.floor(rnd() * 256))
	end

	return {
		empty = "",
		one = "A",
		allbytes = allBytes(),
		text = string.rep("The quick brown fox jumps over the lazy dog. ", 40),
		flat = string.rep("\128", 3000),
		gradient = table.concat(gradient),
		noise = table.concat(noise),
		unicode = string.rep("caf\xc3\xa9 \228\246\252 \240\159\148\128 ", 30),
	}
end

--------------------------------------------------------------------------------
-- helpers

local CODERS = {
	{ compress = "CompressDeflate", decompress = "DecompressDeflate", codec = 4, name = "Deflate" },
	{ compress = "CompressZlib", decompress = "DecompressZlib", codec = 5, name = "Zlib" },
	{ compress = "CompressGzip", decompress = "DecompressGzip", codec = 6, name = "Gzip" },
}

local FILTERS = { "none", "sub", "rle", "auto" }
local LEVELS = { "omit", "speed", "size", 0, 1, 2 }

local function roundtrip(section, name, compressed, original)
	if type(compressed) ~= "string" then
		return check(section .. " " .. name, false, "compress returned " .. tostring(compressed))
	end
	local ok, back = pcall(function() return LibCompress:Decompress(compressed) end)
	if not ok then
		return check(section .. " " .. name, false, "Decompress errored: " .. tostring(back))
	end
	check(section .. " " .. name, back == original,
		("header %d, %d -> %d, decoded %s"):format(compressed:byte(1), #original, #compressed,
		back and (#back .. " bytes") or "nil"))
end

--------------------------------------------------------------------------------
-- tests

local function testLegacy(payloads)
	local section = "legacy"
	local streams = {
		{ "store", "\001hello", "hello" },
	}
	streams[#streams + 1] = { "lzw", LibCompress:CompressLZW(payloads.text), payloads.text }
	streams[#streams + 1] = { "huffman", LibCompress:CompressHuffman(payloads.text), payloads.text }
	for _, case in ipairs(streams) do
		local name, stream, expect = case[1], case[2], case[3]
		check(section .. " " .. name .. " header is unfiltered", stream:byte(1) < 128, stream:byte(1))
		check(section .. " " .. name .. " roundtrip", LibCompress:Decompress(stream) == expect)
	end
	check(section .. " fcs16 update equivalence",
		LibCompress:fcs16String("abcdef") == LibCompress:fcs16final(LibCompress:fcs16update(LibCompress:fcs16update(LibCompress:fcs16init(), "abc"), "def")))
	check(section .. " fcs32 update equivalence",
		LibCompress:fcs32String("abcdef") == LibCompress:fcs32final(LibCompress:fcs32update(LibCompress:fcs32update(LibCompress:fcs32init(), "abc"), "def")))
end

local function testCompress(section, payloads, portable)
	for name, data in pairs(payloads) do
		roundtrip(section, name, LibCompress:Compress(data, portable), data)
	end
end

local function testFilters(section, payloads, portable)
	-- a subset, this multiplies quickly and :Compress() tries every codec per prefilter
	local subset = { empty = payloads.empty, one = payloads.one, text = payloads.text, gradient = payloads.gradient, allbytes = payloads.allbytes }
	for name, data in pairs(subset) do
		for _, filter in ipairs(FILTERS) do
			roundtrip(section .. " " .. filter, name, LibCompress:Compress(data, portable, filter), data)
			if filter ~= "auto" and filter ~= "none" then
				local stream = LibCompress:Compress(data, portable, filter)
				local header = type(stream) == "string" and stream:byte(1) or 0
				local want = (filter == "sub") and 128 or 192
				check(section .. " " .. filter .. " " .. name .. " header bits", bit_band(header, 192) == want, header)
			end
		end
	end
end

local function testStandalone(section, payloads)
	for _, coder in ipairs(CODERS) do
		for name, data in pairs(payloads) do
			local stream = LibCompress[coder.compress](LibCompress, data)
			roundtrip(section .. " " .. coder.name, name, stream, data)
			if type(stream) == "string" then
				check(section .. " " .. coder.name .. " " .. name .. " header", stream:byte(1) == coder.codec, stream:byte(1))
				local ok, back = pcall(function() return LibCompress[coder.decompress](LibCompress, stream) end)
				check(section .. " " .. coder.name .. " " .. name .. " standalone decode", ok and back == data, ok and ("got " .. tostring(back and #back)) or back)
			end
		end
	end
end

local function testStandaloneFiltersAndLevels(section, payloads)
	local samples = { payloads.text, payloads.gradient, payloads.one, payloads.allbytes }
	for _, coder in ipairs(CODERS) do
		for sampleIndex, data in ipairs(samples) do
			for _, filter in ipairs(FILTERS) do
				for _, level in ipairs(LEVELS) do
					local levelArg
					if level ~= "omit" then
						levelArg = level
					end
					local stream = LibCompress[coder.compress](LibCompress, data, levelArg, filter)
					roundtrip(section .. " " .. coder.name,
						("sample%d %s/%s"):format(sampleIndex, filter, tostring(level)), stream, data)
					if type(stream) == "string" and filter ~= "auto" and filter ~= "none" then
						local want = (filter == "sub") and 128 or 192
						check(section .. " " .. coder.name .. " filter bits", bit_band(stream:byte(1), 192) == want, stream:byte(1))
					end
				end
			end
		end
	end
end

local LEGACYCODERS = {
	{ compress = "CompressLZW", decompress = "DecompressLZW", codec = 2 },
	{ compress = "CompressHuffman", decompress = "DecompressHuffman", codec = 3 },
}

local function testLegacyCoderFilters(section, payloads)
	for _, coder in ipairs(LEGACYCODERS) do
		for name, data in pairs(payloads) do
			-- unfiltered calls have to behave exactly as they always did
			local plain = LibCompress[coder.compress](LibCompress, data)
			roundtrip(section .. " " .. coder.compress, name, plain, data)
			if type(plain) == "string" then
				local header = plain:byte(1)
				check(section .. " " .. coder.compress .. " " .. name .. " unfiltered header",
					header == coder.codec or header == 1, header)
			end

			for _, filter in ipairs(FILTERS) do
				local stream = LibCompress[coder.compress](LibCompress, data, filter)
				roundtrip(section .. " " .. coder.compress .. " " .. filter, name, stream, data)
				if type(stream) == "string" then
					local header = stream:byte(1)
					-- the coder may have given up and stored, so only the prefilter bits
					-- are fixed
					check(section .. " " .. coder.compress .. " " .. filter .. " " .. name .. " codec id intact",
						header % 64 == coder.codec or header % 64 == 1, header)
					if filter ~= "auto" and filter ~= "none" then
						local want = (filter == "sub") and 128 or 192
						check(section .. " " .. coder.compress .. " " .. filter .. " " .. name .. " header bits",
							bit_band(header, 192) == want, header)
					end
					local ok, back = pcall(function() return LibCompress[coder.decompress](LibCompress, stream) end)
					check(section .. " " .. coder.compress .. " " .. filter .. " " .. name .. " standalone decode",
						ok and back == data, ok and ("got " .. tostring(back and #back)) or back)
				end
			end
		end
		check(section .. " " .. coder.compress .. " unknown filter rejected",
			(LibCompress[coder.compress](LibCompress, "x", "spaghetti")) == nil)
		check(section .. " " .. coder.compress .. " non string rejected",
			(LibCompress[coder.compress](LibCompress, 1234)) == nil)
	end

	check(section .. " DecompressLZW rejects Huffman data",
		(LibCompress:DecompressLZW(LibCompress:CompressHuffman(payloads.text))) == nil)
	check(section .. " DecompressHuffman rejects LZW data",
		(LibCompress:DecompressHuffman(LibCompress:CompressLZW(payloads.text))) == nil)
	check(section .. " stored filter bits reversed by DecompressUncompressed",
		LibCompress:DecompressUncompressed("\193" .. LibCompress:FilterRLE("\000\000\000")) == "\000\000\000")
	check(section .. " stored filter bits reversed by Decompress",
		LibCompress:Decompress("\129" .. LibCompress:FilterSub("abc")) == "abc")
end

local function testContainersAreNotInterchangeable(section)
	-- each container has its own framing, so decoding one as another must fail rather than
	-- return garbage; a client that hard crashes here is a bug report for Blizzard
	local data = string.rep("container framing check ", 20)
	local streams = {}
	for _, coder in ipairs(CODERS) do
		streams[coder.name] = LibCompress[coder.compress](LibCompress, data)
	end
	for _, a in ipairs(CODERS) do
		for _, b in ipairs(CODERS) do
			if a ~= b then
				local ok, back = pcall(function() return LibCompress[b.decompress](LibCompress, streams[a.name]) end)
				if not ok then
					log(("  note  %s stream decoded as %s errors: %s"):format(a.name, b.name, tostring(back)))
				end
				check(section .. " " .. a.name .. " as " .. b.name, (not ok) or back ~= data, "decoded to the same payload")
			end
		end
	end
end

local function testArgumentHandling()
	local section = "arguments"
	local bad = {
		{ "level out of range", LibCompress:CompressZlib("x", 9) },
		{ "unknown level name", LibCompress:CompressZlib("x", "bananas") },
		{ "unknown filter", LibCompress:CompressZlib("x", nil, "spaghetti") },
		{ "non string payload", LibCompress:CompressZlib(1234) },
		{ "Compress non string", LibCompress:Compress(1234) },
		{ "Compress unknown filter", LibCompress:Compress("x", false, "spaghetti") },
	}
	for _, case in ipairs(bad) do
		check(case[1] .. " rejected", case[2] == nil and type(case[3]) == "string", tostring(case[2]) .. " / " .. tostring(case[3]))
	end
	check("Decompress of an empty string is an error", (LibCompress:Decompress("")) == nil)
	check("Decompress of a non string is an error", (LibCompress:Decompress(7)) == nil)
	check("unknown codec id is an error", (LibCompress:Decompress("\009abcdef")) == nil)
	check("filtered unknown codec id is an error", (LibCompress:Decompress("\201abcdef")) == nil)
end

local function testHostileInput(payloads)
	local section = "hostile input"
	local cases = {
		{ "deflate with a filtered header and garbage", "\132abcdef" },
		{ "gzip header, no data", "\006" },
		{ "rle token past the end", "\251" },
		{ "rle literal run past the end", "\127AB" },
		{ "filtered lzw truncated", (LibCompress:Compress(payloads.text, true, "sub")):sub(1, 6) },
		{ "filtered rle truncated", (LibCompress:Compress(string.rep("\1", 500), true, "rle")):sub(1, 4) },
		{ "unfiltered rle garbage", "\255\1\2\3\254\0\128" },
		{ "filtered store garbage", "\129\255\255\255\1" },
	}
	if LibCompress:HasZlibCodecs() then
		local truncatedDeflate = LibCompress:CompressDeflate(payloads.text)
		local truncatedZlib = LibCompress:CompressZlib(payloads.text)
		cases[#cases + 1] = { "deflate truncated to a byte", truncatedDeflate:sub(1, 1) }
		cases[#cases + 1] = { "deflate truncated in half", truncatedDeflate:sub(1, math.floor(#truncatedDeflate / 2)) }
		cases[#cases + 1] = { "zlib truncated to a byte", truncatedZlib:sub(1, 1) }
		cases[#cases + 1] = { "zlib truncated in half", truncatedZlib:sub(1, math.floor(#truncatedZlib / 2)) }
	end
	for _, case in ipairs(cases) do
		local ok, result = pcall(function() return LibCompress:Decompress(case[2]) end)
		check(case[1] .. " does not error", ok, result)
		check(case[1] .. " returns nil or a string", not ok or result == nil or type(result) == "string")
	end

	-- the prefilters on their own, fed nonsense directly
	local unfilterCases = {
		{ "UnfilterRLE truncated repeat", LibCompress.UnfilterRLE, "\255" },
		{ "UnfilterRLE repeat with no byte", LibCompress.UnfilterRLE, "\250" },
		{ "UnfilterRLE literal run past the end", LibCompress.UnfilterRLE, "\127AB" },
		{ "UnfilterRLE no operation", LibCompress.UnfilterRLE, "\128" },
		{ "UnfilterSub one byte", LibCompress.UnfilterSub, "\65" },
		{ "UnfilterSub empty", LibCompress.UnfilterSub, "" },
	}
	for _, case in ipairs(unfilterCases) do
		local ok, result = pcall(case[2], LibCompress, case[3])
		check(case[1], ok and type(result) == "string", ok and type(result) or result)
	end
end

local function testEncodeTables(payloads)
	local section = "encode tables"
	local addon = LibCompress:GetAddonEncodeTable()
	check("addon encode roundtrip", addon:Decode(addon:Encode(payloads.allbytes)) == payloads.allbytes)
	check("addon encode has no NUL", not addon:Encode(payloads.allbytes):find("\000", 1, true))

	local logged = LibCompress:GetLoggedEncodeTable()
	local encoded = logged:Encode(payloads.allbytes)
	check("logged encode roundtrip", logged:Decode(encoded) == payloads.allbytes,
		("%d -> %d -> %d"):format(#payloads.allbytes, #encoded, #logged:Decode(encoded)))
	check("logged output is printable ascii only", encoded:match("^[^\000-\031\127-\255]*$") ~= nil,
		encoded:gsub("%c", "?"):sub(1, 40))
	check("logged output has no chat escape", not encoded:find("|", 1, true))
	for i = 1, 4 do
		local samples = {
			"Hello ~`^ |cff00ff00Coloured|r|r",
			"\228\246\252\243\245\179 \216\159\166\156\159\010\000\255",
			"",
			"\1\2\3\4\5\6\7\8\9\10\11\12\13",
		}
		local sample = samples[i]
		check("logged encode sample " .. i, logged:Decode(logged:Encode(sample)) == sample, sample ~= "" and sample:byte(1) or "empty")
	end
	local plain = string.rep("plain ascii text with spaces and dots.\n", 20)
	check("logged encoding of ascii is near free", #logged:Encode(plain) <= #plain + 40,
		("%d -> %d"):format(#plain, #logged:Encode(plain)))
	local withExtra = LibCompress:GetLoggedEncodeTable("sS", nil, "\015\020")
	check("logged table takes extra reserved chars", withExtra:Decode(withExtra:Encode("sS")) == "sS")
end

local function testChecksums(payloads)
	-- the RFC 1331 FCS-32 is the same CRC-32 as zlib.crc32, so these are known answers
	local oracle = {
		[""] = { 0, "00000000" },
		["hello"] = { 907060870, "3610a686" },
		["123456789"] = { 3421780262, "cbf43926" },
		[payloads.allbytes] = { 688229491, "29058c73" },
	}
	for data, expected in pairs(oracle) do
		local label = "fcs32 " .. (data == "" and "<empty>" or data:sub(1, 6):gsub("%c", "."))
		check(label, LibCompress:fcs32String(data) == expected[1],
			tostring(LibCompress:fcs32String(data)) .. " vs " .. expected[1])
		check(label .. " hex", LibCompress:fcs32Hex(data) == expected[2], tostring(LibCompress:fcs32Hex(data)))
	end
	check("fcs16Hex width", #LibCompress:fcs16Hex("hello") == 4, LibCompress:fcs16Hex("hello"))
	check("checksums are stable", LibCompress:fcs32Hex("abc") == LibCompress:fcs32Hex("abc"))
	check("checksums change with the data", LibCompress:fcs32Hex("abc") ~= LibCompress:fcs32Hex("abd"))
	check("fcs32String rejects non strings", (LibCompress:fcs32String(42)) == nil)
end

local function sizeReport(payloads)
	log("")
	log("size report (bytes)")
	log(("%-10s %7s %7s %7s %7s %7s %7s %7s %7s %7s %7s"):format(
		"payload", "raw", "lzw", "huff", "lzw+sub", "huff+sub", "defl", "zlib", "gzip", "defl+sub", "zlib+auto"))
	for _, name in ipairs({ "empty", "one", "allbytes", "text", "flat", "gradient", "noise", "unicode" }) do
		local data = payloads[name]
		local function n(value)
			return type(value) == "string" and #value or -1
		end
		log(("%-10s %7d %7d %7d %7d %7d %7d %7d %7d %7d %7d"):format(
			name, #data,
			n(LibCompress:CompressLZW(data)),
			n(LibCompress:CompressHuffman(data)),
			n(LibCompress:CompressLZW(data, "sub")),
			n(LibCompress:CompressHuffman(data, "sub")),
			n(LibCompress:CompressDeflate(data)),
			n(LibCompress:CompressZlib(data)),
			n(LibCompress:CompressGzip(data)),
			n(LibCompress:CompressDeflate(data, nil, "sub")),
			n(LibCompress:CompressZlib(data, nil, "auto"))))
	end

	log("")
	log("timing, 3000 byte payload, ms per call")
	local data = payloads.text
	for _, case in ipairs({
		{ "CompressLZW", function() return LibCompress:CompressLZW(data) end },
		{ "CompressLZW sub", function() return LibCompress:CompressLZW(data, "sub") end },
		{ "CompressLZW auto", function() return LibCompress:CompressLZW(data, "auto") end },
		{ "CompressHuffman", function() return LibCompress:CompressHuffman(data) end },
		{ "CompressHuffman sub", function() return LibCompress:CompressHuffman(data, "sub") end },
		{ "CompressZlib", function() return LibCompress:CompressZlib(data) end },
		{ "CompressZlib sub", function() return LibCompress:CompressZlib(data, nil, "sub") end },
		{ "Compress auto", function() return LibCompress:Compress(data, false, "auto") end },
		{ "Compress portable", function() return LibCompress:Compress(data, true) end },
	}) do
		local iterations = 20
		local start = debugprofilestop()
		for _ = 1, iterations do
			case[2]()
		end
		log(("  %-18s %6.2f"):format(case[1], (debugprofilestop() - start) / iterations))
	end
end

--------------------------------------------------------------------------------
-- runner

local function run()
	if LibStub and not LibStub:GetLibrary("LibCompress", true) then
		LoadAddOn("LibCompress")
	end
	LibCompress = LibStub and LibStub:GetLibrary("LibCompress", true)
	if not LibCompress then
		print("LibCompressTest: LibCompress is not loaded - enable PhotoFinger, or add the LibCompress folder to your AddOns")
		return
	end

	-- an old copy of the library somewhere else in AddOns can win the LibStub
	-- registration, and then every test below would be testing the wrong file
	local minor = LibStub.minors and LibStub.minors["LibCompress"]
	if not minor or minor < EXPECTED_MINOR then
		print(("LibCompressTest: not testing - LibCompress %s is loaded, this test needs %d or newer")
			:format(tostring(minor), EXPECTED_MINOR))
		return
	end

	passed, failed, report = 0, 0, {}
	local payloads = buildPayloads()

	log(("LibCompressTest  LibCompress %s  zlib codecs available: %s  build %s"):format(
		tostring(minor), tostring(LibCompress:HasZlibCodecs() or false), GetBuildInfo()))

	if not LibCompress:HasZlibCodecs() then
		log("C_EncodingUtil is missing, only the pure Lua paths are being tested")
	end

	testLegacy(payloads)
	testCompress(":Compress", payloads, false)
	testCompress(":Compress portable", payloads, true)
	testFilters(":filter", payloads, false)
	testFilters(":filter portable", payloads, true)
	testLegacyCoderFilters("legacy filters", payloads)
	if LibCompress:HasZlibCodecs() then
		testStandalone("standalone", payloads)
		testStandaloneFiltersAndLevels("standalone opts", payloads)
		testContainersAreNotInterchangeable("containers")
	end
	testArgumentHandling()
	testHostileInput(payloads)
	testEncodeTables(payloads)
	testChecksums(payloads)
	sizeReport(payloads)

	log("| ------------------------------------------------------------")
	log(("%d passed, %d failed"):format(passed, failed))
	LibCompressTest.lastReport = table.concat(report, "\n")
end

SLASH_LIBCOMPRESSTEST1 = "/lctest"
SlashCmdList.LIBCOMPRESSTEST = function(msg)
	if (msg or ""):match("^%s*copy") then
		if LibCompressTest.lastReport then
			CopyToClipboard(LibCompressTest.lastReport, true)
			print("LibCompressTest: report copied to the clipboard")
		end
		return
	end
	run()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self, event, initial)
	if event == "PLAYER_ENTERING_WORLD" then
		print("/lctest - LibCompress test driver")
	end
end)
