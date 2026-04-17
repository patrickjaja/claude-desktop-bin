# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim

import std/os
import regex

proc apply*(input: string): string =
  let pattern = re2"(const \w+=\(\w+=this\.process\)==null\?void 0:\w+)(\.kill\(\))(;[\w$]+\.info\(`Killing utiltiy proccess again)"
  var count = 0
  result = input.replace(pattern, proc (m: RegexMatch2, s: string): string =
    inc count
    s[m.group(0)] & "\x2ekill(\"SIGKILL\")" & s[m.group(2)]
  )
  if count == 0:
    raise newException(ValueError, "fix_utility_process_kill: pattern not found")

when isMainModule:
  let file = paramStr(1)
  echo "=== Patch: fix_utility_process_kill ==="
  writeFile(file, apply(readFile(file)))
  echo "  [PASS]"
