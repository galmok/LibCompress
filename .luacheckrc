std = "lua51"
max_line_length = false
unused_args = false

globals = {
	"LibStub",
	"CreateFrame",
	"GetBuildInfo",
	"GetTime",
	"GetLastError",
	"LoadAddOn",
	"IsAddOnLoaded",
	"SlashCmdList",
	"SLASH_LIBCOMPRESSTEST1",
	"UIParent",
	"Enum",
	"C_EncodingUtil",
	"C_ChatInfo",
	"C_AddOns",
	"bit",
	"sort",
	"debugprofilestop",
}

-- development helpers, they deliberately fake the WoW environment
exclude_files = {
	"Tools",
}
