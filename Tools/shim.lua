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

-- Lua 5.1 reads patterns as C strings and truncates them at an embedded NUL, while
-- modern Lua does not. Emulate the old behaviour so pattern bugs fail here too.
do
	local function truncate(pattern, plain)
		if type(pattern) == "string" and not plain then
			local cut = pattern:find("\000", 1, true)
			if cut then
				return pattern:sub(1, cut - 1)
			end
		end
		return pattern
	end

	local find, match, gmatch, gsub = string.find, string.match, string.gmatch, string.gsub
	string.find = function(s, pattern, init, plain) return find(s, truncate(pattern, plain), init, plain) end
	string.match = function(s, pattern) return match(s, truncate(pattern)) end
	string.gmatch = function(s, pattern) return gmatch(s, truncate(pattern)) end
	string.gsub = function(s, pattern, repl, count) return gsub(s, truncate(pattern), repl, count) end
end

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

-- Only methods a plain retail frame actually has. Anything else has to fail here
-- instead of on the live client, so the widget stubs stay close to the real API.
local widgetMethods = {
	RegisterEvent = true, UnregisterEvent = true, RegisterAllEvents = true,
	RegisterForDrag = true, RegisterForClicks = true,
	SetScript = true, Show = true, Hide = true, IsShown = true,
	SetPoint = true, ClearAllPoints = true, SetSize = true, SetWidth = true, SetHeight = true,
	GetWidth = true, GetHeight = true, SetParent = true, GetParent = true,
	SetFrameStrata = true, SetFrameLevel = true, SetToplevel = true, SetMovable = true,
	EnableMouse = true, EnableMouseWheel = true, EnableKeyboard = true, SetAlpha = true,
	StartMoving = true, StopMovingOrSizing = true, SetPropagate = true,
	CreateFontString = true, CreateTexture = true, CreateMaskTexture = true,
	SetText = true, GetText = true, SetFontObject = true, GetFontObject = true,
	SetMultiLine = true, SetAutoFocus = true, SetMaxLetters = true, SetFocus = true,
	HasFocus = true, HighlightText = true,
}

local function newWidget()
	local state = { width = 0, height = 0, shown = false }
	local widget
	widget = setmetatable({}, {
		__index = function(self, key)
			if not widgetMethods[key] then return nil end
			if key == "SetScript" then
				return function(_, script, handler) rawset(self, script, handler) end
			end
			return function(_, ...)
				if key == "SetSize" then
					state.width, state.height = ...
				elseif key == "SetWidth" then
					state.width = ...
				elseif key == "SetHeight" then
					state.height = ...
				elseif key == "GetWidth" then
					return state.width
				elseif key == "GetHeight" then
					return state.height
				elseif key == "Show" then
					state.shown = true
				elseif key == "Hide" then
					state.shown = false
				elseif key == "IsShown" then
					return state.shown
				elseif key == "SetText" then
					state.text = ...
				elseif key == "GetText" then
					return state.text
				elseif key == "CreateFontString" or key == "CreateTexture" or key == "CreateMaskTexture" then
					return newWidget()
				end
			end
		end,
	})
	return widget
end

function CreateFrame(frameType, name, parent, template)
	return newWidget()
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
