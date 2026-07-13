# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Parent side of the M365 OAuth browser-open delegation (issue #139, KDE).
#
# The built-in MCP host's parent<->child message handler (a flat if-chain that
# only knows msal-cache-get / msal-cache-set, wired via
# this.process.on("message", ...)) gains a new first branch:
#
#   {type:"open-url", url:"https://..."}  ->  shell.openExternal(url)
#
# This is the exact mechanism the remote-OAuth (Atlassian) flow uses, which is
# why that connector opens the browser fine on every DE while the local M365
# connector's in-child spawn("xdg-open") fails on KDE. The child side is
# patched by fix_office365_mcp_open_url.nim; both are required together.
#
# Safety: the branch only accepts string URLs starting with https:// so a
# compromised MCP child cannot open file:// or other schemes via the parent.
#
# Anchors: the unique "msal-cache-get" literal for the injection site, plus the
# electron namespace var recovered from X.safeStorage.decryptString( within the
# SAME code-split chunk as the injection site. Since v1.20186.1 the bundle is
# split into 82 chunks (separated by /*__CDB_SPLIT__<name>__*/ markers by the
# orchestrator) and each chunk is a distinct runtime module with its own
# electron require: a bundle-wide safeStorage scan now sees several vars (e.g.
# x in the MSAL host chunk, ne in an unrelated token-cache chunk). We therefore
# scope the scan to the injection-site chunk, where the var is unambiguous.
# All minified identifiers ([\w$]+) are captured and reused.

import std/[os, strutils, sets]
import regex

const SPLIT_MARKER = "/*__CDB_SPLIT__"

proc apply*(input: string): string =
  # Idempotency: positive end-state -- the open-url branch must be present.
  if """==="open-url"&&typeof""" in input:
    echo "  [OK] built-in MCP open-url handler: already patched"
    return input

  # Step 1: inject the branch at the head of the child-message if-chain.
  # Matches (v1.20186.1): };return(d,f)=>{const p=d;if((p==null?void 0:p.type)==="msal-cache-get"
  # Groups: 0=head incl. "const p=d;", 1=message param, 2=message var,
  # 3=original if-head.
  let pattern =
    re2"""(\};return\(([\w$]+),[\w$]+\)=>\{const ([\w$]+)=[\w$]+;)(if\(\([\w$]+==null\?void 0:[\w$]+\.type\)==="msal-cache-get")"""

  # Locate the injection site so we can scope the electron-var scan to its chunk.
  var injMatches: seq[RegexMatch2] = @[]
  for m in input.findAll(pattern):
    injMatches.add(m)
  if injMatches.len != 1:
    echo "  [FAIL] built-in MCP open-url handler: found " & $injMatches.len &
      " msal-cache-get injection sites (expected 1)"
    quit(1)
  let injPos = injMatches[0].boundaries.a

  # Step 2: recover the electron namespace var from within the injection-site
  # chunk only. The chunk spans from the split marker preceding injPos to the
  # next split marker after it (or the buffer ends). safeStorage.decryptString(
  # is used by the MSAL host module and resolves to a single electron var here.
  var chunkStart = input.rfind(SPLIT_MARKER, last = injPos)
  if chunkStart < 0:
    chunkStart = 0
  var chunkEnd = input.find(SPLIT_MARKER, start = injPos)
  if chunkEnd < 0:
    chunkEnd = input.len
  let chunk = input[chunkStart ..< chunkEnd]

  var electronVars = initHashSet[string]()
  for m in chunk.findAll(re2"([\w$]+)\.safeStorage\.decryptString\("):
    electronVars.incl(chunk[m.group(0)])
  if electronVars.len != 1:
    echo "  [FAIL] built-in MCP open-url handler: expected exactly 1 distinct " &
      "electron ns var via safeStorage.decryptString in the injection-site " &
      "chunk, found " & $electronVars.len
    quit(1)
  var electronVar = ""
  for v in electronVars:
    electronVar = v

  var count = 0
  result = input.replace(
    pattern,
    proc(m: RegexMatch2, s: string): string =
      inc count
      let head = s[m.group(0)]
      let msgVar = s[m.group(2)]
      let ifHead = s[m.group(3)]
      head & "if((" & msgVar & "==null?void 0:" & msgVar &
        ".type)===\"open-url\"&&typeof " & msgVar & ".url==\"string\"&&" & msgVar &
        ".url.startsWith(\"https://\")){" & electronVar & ".shell.openExternal(" & msgVar &
        ".url).catch(()=>{});return}" & ifHead,
  )

  if count != 1:
    echo "  [FAIL] built-in MCP open-url handler: " & $count & " matches (expected 1)"
    quit(1)

  echo "  [OK] built-in MCP open-url handler: shell.openExternal branch added"

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_builtin_mcp_open_url_handler <file>"
    quit(1)
  let filePath = paramStr(1)
  echo "=== Patch: fix_builtin_mcp_open_url_handler ==="
  echo "  Target: " & filePath
  let input = readFile(filePath)
  let output = apply(input)
  writeFile(filePath, output)
  echo "  [PASS] built-in MCP open-url handler patched successfully"
