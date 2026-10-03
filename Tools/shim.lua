-- Minimal WoW API surface so LibCompress and its test driver run under plain Lua.

unpack = table.unpack
loadstring = load
strmatch = string.match
sort = table.sort
tinsert = table.insert
tremove = table.remove
strtrim = string.trim or function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
wipe = function(t) for k in pairs(t) do t[k] = nil end end
UIParent = {}

-- WoW's 32 bit bit library
do
	local MASK = 0xFFFFFFFF
	bit = {
		band   = function(a, b) return a & b end,
		bor    = function(a, b) return a | b end,
		bxor   = function(a, b) return a ~ b end,
		bnot   = function(a) return (~a) & MASK end,
		lshift = function(a, n) return (a << n) & MASK end,
		rshift = function(a, n) return (a & MASK) >> n end,
	}
end

local function noop() end

function CreateFrame(frameType, name, parent, template)
	local frame = {}
	frame.RegisterEvent = noop
	frame.UnregisterEvent = noop
	frame.SetScript = function(self, script, handler) frame[script] = handler end
	frame.Show, frame.Hide = noop, noop
	frame.IsShown = function() return false end
	frame.SetPropagate = noop
	return frame
end

function GetBuildInfo() return "12.1.0", 120100, "Release", "2026-10-03", 43000 end

if not debugprofilestop then
	debugprofilestop = function() return os.clock() * 1000 end
end

SlashCmdList = {}
function LoadAddOn() return nil end
C_AddOns = {
	LoadAddOn = LoadAddOn,
	DoesAddOnExist = function() return true end,
	IsAddOnLoaded = function() return true end,
	GetAddOnInfo = function() return "Lib: Compress", nil, true end,
}
function GetLastError() return "" end
