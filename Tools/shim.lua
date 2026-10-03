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
	SetVerticalScroll = true, GetVerticalScroll = true, GetVerticalScrollRange = true,
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
				elseif key == "GetVerticalScrollRange" then
					return 0
				elseif key == "GetVerticalScroll" then
					return 0
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
