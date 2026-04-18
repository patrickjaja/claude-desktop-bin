# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Patch Quick Entry to spawn on cursor's monitor and auto-focus input.
# Four patches: position function, fallback display, position restore, show/focus fix.
# Uses std/nre for backreference support in patterns.

import std/[os, strformat, options]
import std/nre

proc cursorIife(electronVar: string): string =
  "(()=>{" &
  "if(process.platform===\"linux\"){" &
  "const cp=require(\"child_process\");" &
  "try{" &
  "const r=cp.execFileSync(\"xdotool\",[\"getmouselocation\",\"--shell\"]," &
  "{timeout:200,encoding:\"utf-8\"});" &
  "const x=parseInt(r.match(/X=(\\d+)/)?.[1]);" &
  "const y=parseInt(r.match(/Y=(\\d+)/)?.[1]);" &
  "if(!isNaN(x)&&!isNaN(y)){if(!globalThis.__qeCursorLogged){globalThis.__qeCursorLogged=true;console.log(\"[quick-entry] cursor: using xdotool\")}return{x,y}}" &
  "}catch(e){}" &
  "try{" &
  "const r=cp.execFileSync(\"hyprctl\",[\"cursorpos\"]," &
  "{timeout:200,encoding:\"utf-8\"});" &
  "const m=r.match(/(\\d+),\\s*(\\d+)/);" &
  "if(m){if(!globalThis.__qeCursorLogged){globalThis.__qeCursorLogged=true;console.log(\"[quick-entry] cursor: using hyprctl\")}return{x:parseInt(m[1]),y:parseInt(m[2])}}" &
  "}catch(e){}" &
  "if(!globalThis.__qeCursorLogged){globalThis.__qeCursorLogged=true;console.warn(\"[quick-entry] cursor: xdotool/hyprctl not available -- falling back to Electron API (may show on wrong monitor)\")}" &
  "}" &
  "return " & electronVar & ".screen.getCursorScreenPoint()" &
  "})()"

proc apply*(input: string): string =
  result = input
  var failed = false

  # Patch 1: Position function -- getPrimaryDisplay -> getDisplayNearestPoint
  # No backreference needed here
  let pattern1 = re"(function [\w$]+\(\)\{const [\w$]+=)([\w$]+)(\.screen\.)getPrimaryDisplay\(\)"
  var count1 = 0
  result = result.replace(pattern1, proc(m: RegexMatch): string =
    inc count1
    let electronVar = m.captures[1]
    let cursor = cursorIife(electronVar)
    m.captures[0] & m.captures[1] & m.captures[2] & "getDisplayNearestPoint(" & cursor & ")"
  )
  if count1 > 0:
    echo &"  [OK] position function: {count1} match(es)"
  else:
    echo "  [FAIL] position function: 0 matches, expected >= 1"
    failed = true

  # Patch 2 (optional): Fallback display lookup -- uses \1 backreference
  let pattern2 = nre.re"([\w$])\|\|\(\1=([\w$]+)\.screen\.getPrimaryDisplay\(\)\)"
  var count2 = 0
  # findAll + manual replace
  var pos = 0
  var resultStr = ""
  for m in result.findIter(pattern2):
    inc count2
    let varName = m.captures[0]
    let electronVar = m.captures[1]
    let cursor = cursorIife(electronVar)
    resultStr &= result[pos ..< m.matchBounds.a]
    resultStr &= varName & "||(" & varName & "=" & electronVar & ".screen.getDisplayNearestPoint(" & cursor & "))"
    pos = m.matchBounds.b + 1
  if count2 > 0:
    resultStr &= result[pos .. ^1]
    result = resultStr
    echo &"  [OK] fallback display: {count2} match(es)"
  else:
    echo "  [INFO] fallback display: 0 matches (pattern removed in this version, optional)"

  # Patch 3: Override position-restore to always use cursor's display
  # No backreferences needed
  let pattern3 = re"""(function [\w$]+\(\)\{const [\w$]+=[\w$]+\.get\("quickWindowPosition",null\),[\w$]+=[\w$]+\.screen\.getAllDisplays\(\);if\(!\()[\w$]+&&[\w$]+\.absolutePointInWorkspace&&[\w$]+\.monitor&&[\w$]+\.relativePointFromMonitor(\)\)return )([\w$]+)\(\)"""
  var count3 = 0
  result = result.replace(pattern3, proc(m: RegexMatch): string =
    inc count3
    m.captures[0] & "!1" & m.captures[1] & m.captures[2] & "()"
  )
  if count3 > 0:
    echo &"  [OK] position restore override: {count3} match(es)"
  else:
    echo "  [INFO] position restore override: 0 matches (older version without saved position)"

  # Patch 4: Fix show/positioning + focus on Linux -- uses \1, \2 backreferences
  let pattern4 = nre.re"([\w$]+)\.show\(\)\}return \1\.setPosition\(Math\.round\(([\w$]+)\.x\),Math\.round\(\2\.y\)\),!0\}"
  let m4 = result.find(pattern4)
  if m4.isSome:
    let m = m4.get
    let w = m.captures[0]
    let v = m.captures[1]
    let replacement =
      "(()=>{" &
      "const _b={x:Math.round(" & v & ".x),y:Math.round(" & v & ".y)," &
      "width:" & w & ".getBounds().width,height:" & w & ".getBounds().height};" &
      "const _r=()=>{" & w & ".isDestroyed()||" & w & ".setBounds(_b)};" &
      "const _ef=()=>{if(" & w & ".isDestroyed())return;" &
      w & ".moveTop();" & w & ".focus();" & w & ".focusOnWebView();" &
      w & ".webContents.focus();" &
      w & ".webContents.executeJavaScript(" &
      "'document.getElementById(\"prompt-input\")?.focus()'" &
      ").catch(()=>{})};" &
      "const _isX11=process.platform===\"linux\"&&(" &
      "process.env.XDG_SESSION_TYPE===\"x11\"" &
      "||process.argv.some(a=>a===\"--ozone-platform=x11\")" &
      "||(!process.env.XDG_SESSION_TYPE&&!process.env.WAYLAND_DISPLAY));" &
      "const _xf=()=>{if(!_isX11||" & w & ".isDestroyed())return;" &
      "try{" &
      "const cp=require(\"child_process\");" &
      "const wid=" & w & ".getNativeWindowHandle().readUInt32LE(0);" &
      "cp.execFile(\"xdotool\",[\"windowactivate\",\"--sync\",String(wid)]," &
      "{timeout:500},(e)=>{if(!" & w & ".isDestroyed()){_ef()}});" &
      "}catch(e){_ef()}};" &
      "const _ff=()=>{_ef();if(_isX11){_xf()}};" &
      w & ".setBounds(_b);" &
      w & ".show();" &
      "_r();" &
      "_ff();" &
      "setTimeout(()=>{if(!" & w & ".isDestroyed()){_r();_ff()}},50);" &
      "setTimeout(()=>{if(!" & w & ".isDestroyed()){_r();_ff()}},150);" &
      "setTimeout(()=>{if(!" & w & ".isDestroyed()){_r();_ff()}},300)" &
      "})()}" &
      "return!0}"
    result = result[0 ..< m.matchBounds.a] & replacement & result[m.matchBounds.b + 1 .. ^1]
    echo "  [OK] show/focus ordering fix: 1 match(es)"
  else:
    echo "  [FAIL] show/focus ordering: 0 matches"
    failed = true

  if failed:
    raise newException(ValueError, "fix_quick_entry_position: Required patterns did not match")

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_quick_entry_position <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_quick_entry_position ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output != input:
    writeFile(file, output)
    echo "  [PASS] Quick Entry position patched successfully"
  else:
    echo "  [WARN] No changes made (patterns may have already been applied)"
