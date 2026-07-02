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
# Anchors: the unique "msal-cache-get" literal for the injection site, plus
# the bundle-wide electron namespace var recovered from
# X.safeStorage.decryptString( (all occurrences use the same minified var; the
# patch asserts that consistency). All minified identifiers ([\w$]+) are
# captured and reused.

import std/[os, strutils, sets]
import regex

proc apply*(input: string): string =
  # Idempotency: positive end-state -- the open-url branch must be present.
  if """==="open-url"&&typeof""" in input:
    echo "  [OK] built-in MCP open-url handler: already patched"
    return input

  # Step 1: recover the electron namespace var (aA in v1.17377.x). Every
  # X.safeStorage.decryptString( in the bundle uses the same X; assert it.
  var electronVars = initHashSet[string]()
  for m in input.findAll(re2"([\w$]+)\.safeStorage\.decryptString\("):
    electronVars.incl(input[m.group(0)])
  if electronVars.len != 1:
    echo "  [FAIL] built-in MCP open-url handler: expected exactly 1 distinct " &
      "electron ns var via safeStorage.decryptString, found " & $electronVars.len
    quit(1)
  var electronVar = ""
  for v in electronVars:
    electronVar = v

  # Step 2: inject the branch at the head of the child-message if-chain.
  # Matches (v1.17377.x): };return(g,l)=>{const u=g;if((u==null?void 0:u.type)==="msal-cache-get"
  # Groups: 0=head incl. "const u=g;", 1=message param, 2=message var,
  # 3=original if-head.
  let pattern =
    re2"""(\};return\(([\w$]+),[\w$]+\)=>\{const ([\w$]+)=[\w$]+;)(if\(\([\w$]+==null\?void 0:[\w$]+\.type\)==="msal-cache-get")"""

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
