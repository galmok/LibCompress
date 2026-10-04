# LibCompress

WoW compression library. GPL-2.0. CurseForge project `14273` (slug `libcompress`),
source `galmok/LibCompress`. Primary author: Galmok; JJSheets is the former author.

## Layout

- `LibCompress.lua` - the library. `lib.xml` loads it, `LibCompress.toc` is the TOC.
- `LibCompressTest/` - in-game test driver, excluded from the packaged zip.
- `Tools/` - offline harness that runs the same driver under plain Lua.
- `Libs/LibStub/` - fetched external, gitignored. Refresh with
  `svn export https://repos.curseforge.com/wow/libstub/trunk Libs/LibStub`.

The working copy is `C:\Users\bme\source\repos\LibCompress`. The WoW client sees it
through junctions: `AddOns\LibCompress`, `AddOns\LibCompressTest`, and
`AddOns\PhotoFinger\Libs\LibCompress`. Never copy files into those junction paths.

## Verifying changes

Run all of these before committing; the in-game run is the only one that covers
`C_EncodingUtil`.

    luac -p LibCompress.lua LibCompressTest/LibCompressTest.lua

    cd Tools
    LIBSTUB=../Libs/LibStub/LibStub.lua LIBCOMPRESS=../LibCompress.lua \
        DRIVER=../LibCompressTest/LibCompressTest.lua lua run.lua

    LIBSTUB=../Libs/LibStub/LibStub.lua NEWLIB=../LibCompress.lua RECORDS=cap1.bin lua cross-new.lua
    OLDLIB=old/LibCompress.lua LIBSTUB=../Libs/LibStub/LibStub.lua RECORDS=cap1.bin lua cross-old.lua

In game: `/reload`, then `/lctest`. Expect `931 passed, 0 failed` and a size report.
`/lctest copy` opens the report in a window (Ctrl+A, Ctrl+C).

Streams produced by capability 1 must stay decodable by r83 and r86 forever. The
cross-version check proves it; `Tools/old/` holds the old library and is gitignored.

## WoW and Lua 5.1 traps

Each of these was hit once and cost an in-game run.

- Lua 5.1 has no hex escapes: `\xc3` becomes the literal text `xc3`. CI rejects the
  escape in any `.lua` file. Use decimal escapes.
- Lua 5.1 reads patterns as C strings and truncates them at an embedded NUL, which
  turns `"^[^\000-\031]*$"` into a malformed pattern. `Tools/shim.lua` emulates this
  because the local Lua is 5.5.
- `bit_band` and friends are locals inside `LibCompress.lua`, not globals. WoW only
  provides `bit.band`.
- 11.x removed the addon globals: use `C_AddOns.LoadAddOn`, `C_AddOns.GetAddOnInfo`.
- `NewFontString` is not available on a plain frame; use `CreateFontString`.
- `SetFontObject("SomeName")` errors when the client does not know that name; look the
  font object up in `_G` first.
- `CopyToClipboard` is protected and cannot be called from an addon.
- `EditBox` has no `GetVerticalScrollRange`.
- A UTF-8 BOM in front of `## Interface:` breaks the comma separated interface list.
- Clients that do not understand the comma list stop at the first value, so the
  Classic Era version must come first: `## Interface: 11509, 20506, 120100`.
- `C_EncodingUtil.CompressString`/`DecompressString` raise on corrupt or truncated
  input instead of returning nil. Keep the `pcall` wrappers.

## Releasing

Any tag except `baseline-*` builds a zip and uploads it to CurseForge. Do not tag
casually.

1. Update `CHANGELOG.md`; it is the release text (`manual-changelog` in `.pkgmeta`).
2. Run the verification steps above, including a green `/lctest`.
3. `git tag -a rNN-alpha -m "..." && git push origin rNN-alpha`
   A tag containing `alpha` or `beta` sets the CurseForge release type.
4. Check it: `gh run list`, `gh run view <id> --log`, `gh release view <tag>`.
   Look for `Uploading LibCompress-<tag>.zip ... Success!`.
5. After the alpha is verified, tag the same commit `rNN-release`.

`baseline-r86` marks the last pre-r87 commit so generated history stays readable.
Keep it.

CurseForge automatic packaging must stay **off** on the project page; the GitHub
Action is the packager. The `CF_API_TOKEN` Actions secret is what enables the upload,
and that same upload is what sets the LibStub embedded-library relation.

## Contracts that must not break

- `:Compress(data)` with no capability stays at capability 1 forever.
- Header byte: low 6 bits codec id, bit 7 filtered, bit 6 selector. Existing values are
  frozen; only append.
- Lossy image quantization does not belong in this library.
