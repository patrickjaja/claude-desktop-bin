# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
# Replace Windows-centric "VM service not running" errors with helpful
# Linux messages that guide users to install claude-cowork-service, and
# make sure that message actually reaches the UI (Patch C) instead of being
# swallowed when the Cowork VM startup fails before the web view exists.

import std/[os, strformat, strutils, options]
import std/nre

const EXPECTED_PATCHES = 3

proc replaceOnce(s, sub, by: string): string =
  ## Replace only the first occurrence of `sub` with `by`.
  let idx = s.find(sub)
  if idx < 0:
    return s
  result = s[0 ..< idx] & by & s[idx + sub.len .. ^1]

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0

  # Patch A: ENOENT / retry-exhausted error
  let oldA = "\"VM service not running. The service failed to start.\""
  let newA =
    "(process.platform===\"linux\"" & "?\"Cowork requires claude-cowork-service. " &
    "Install it from https://github.com/patrickjaja/claude-cowork-service, " &
    "then restart Claude Desktop.\"" &
    ":\"VM service not running. The service failed to start.\")"

  if oldA in result:
    result = result.replaceOnce(oldA, newA)
    echo "  [OK] Startup error message: replaced"
    patchesApplied += 1
  else:
    echo "  [WARN] Startup error message not found"

  # Patch B: Timeout fallback error
  let oldB = "throw new Error(\"VM service not running.\")"
  let newB =
    "throw new Error(process.platform===\"linux\"" & "?\"Cowork service not responding. " &
    "Make sure claude-cowork-service is running " &
    "(https://github.com/patrickjaja/claude-cowork-service), " &
    "then restart Claude Desktop.\"" & ":\"VM service not running.\")"

  if oldB in result:
    result = result.replaceOnce(oldB, newB)
    echo "  [OK] Timeout error message: replaced"
    patchesApplied += 1
  else:
    echo "  [WARN] Timeout error message not found"

  # Patch C: Replay the stored startup error once the mainView is ready.
  #
  # When the Cowork VM startup fails (e.g. claude-cowork-service is not
  # running on Linux) BEFORE the web view exists, the dispatcher function
  # stores the error in a module var but only logs
  #   "Cannot dispatch startup error (no mainView): <err>"
  # and never replays it. The error then propagates up VM:start and, left
  # uncaught, crash-loops the app (or, when raised on chat-open, bounces the
  # renderer back to the start screen). Either way the user never sees our
  # "install claude-cowork-service" message. (Confirmed in cowork_vm_node.log:
  # "[VM:start] VM boot failed: ..." + "Cannot dispatch startup error (no
  # mainView): ...".)
  #
  # Upstream shape (names minified, change every release):
  #   function h6(A){var e;H_=A,me!=null&&me.webContents&&!me.webContents
  #     .isDestroyed()?($e.info(`Dispatching startup error: ${A}`),(e=PAA
  #     .getDispatcher(me.webContents))==null||e.dispatchStartupError(A))
  #     :$e.warn(`Cannot dispatch startup error (no mainView): ${A}`)}
  #
  # We rewrite the no-mainView else-branch: keep the warn, then install a
  # one-shot poller that waits (up to ~30s) for the view's webContents to
  # exist and finish loading, then re-dispatches the stored error through the
  # same dispatcher. Idempotent via a globalThis guard so the timer is set up
  # at most once per stored error. Anchored on the unique literal
  # "Cannot dispatch startup error (no mainView): " so we hit only h6, with
  # every minified identifier captured from the match (no hardcoded names).
  block:
    let pat = re(
      "(function ([\\w$]+)\\(([\\w$]+)\\)\\{var ([\\w$]+);" & "([\\w$]+)=\\3," &
        # H_=A  -> stored err var = arg
      "([\\w$]+)!=null&&\\6\\.webContents&&!\\6\\.webContents\\.isDestroyed\\(\\)\\?\\(" &
        # me guard
      "([\\w$]+)\\.info\\(`Dispatching startup error: \\$\\{\\3\\}`\\)," & # $e.info
      "\\(\\4=([\\w$]+)\\.getDispatcher\\(\\6\\.webContents\\)\\)==null\\|\\|" &
        # PAA.getDispatcher
      "\\4\\.dispatchStartupError\\(\\3\\)\\):" &
        "\\7\\.warn\\(`Cannot dispatch startup error \\(no mainView\\): \\$\\{\\3\\}`\\))(\\})"
    )
    let maybe = result.find(pat)
    if maybe.isSome:
      let m = maybe.get()
      let argVar = m.captures[2] # A
      let tmpVar = m.captures[3] # e
      let viewVar = m.captures[5] # me
      let logVar = m.captures[6] # $e
      let dispVar = m.captures[7] # PAA
      let head = m.captures[0] # everything up to and incl. the warn(...) call
      let tail = m.captures[8] # closing }

      # Replay poller: appended after the existing warn(), inside h6.
      let replay =
        ";if(process.platform===\"linux\"&&!globalThis.__cdbStartupErrReplay){" &
        "globalThis.__cdbStartupErrReplay=true;" &
        "var __cdbN=0,__cdbT=setInterval(function(){" & "__cdbN++;" & "try{" & "if(" &
        viewVar & "!=null&&" & viewVar & ".webContents&&!" & viewVar &
        ".webContents.isDestroyed()&&!" & viewVar & ".webContents.isLoading()){" &
        "clearInterval(__cdbT);globalThis.__cdbStartupErrReplay=false;" & "var __cdbD=" &
        dispVar & ".getDispatcher(" & viewVar & ".webContents);" & "if(__cdbD){" & logVar &
        ".info(\"[cdb] Replaying deferred startup error to mainView\");" &
        "__cdbD.dispatchStartupError(" & argVar & ");}" &
        "}else if(__cdbN>300){clearInterval(__cdbT);globalThis.__cdbStartupErrReplay=false;}" &
        "}catch(__cdbE){clearInterval(__cdbT);globalThis.__cdbStartupErrReplay=false;}" &
        "},100);}"

      let bounds = m.matchBounds
      result =
        result[0 ..< bounds.a] & head & replay & tail & result[bounds.b + 1 .. ^1]
      discard tmpVar
      echo &"  [OK] C startup-error replay: installed (view={viewVar}, disp={dispVar})"
      patchesApplied += 1
    else:
      echo "  [FAIL] C startup-error replay: dispatcher (no mainView) pattern not found"

  if patchesApplied < EXPECTED_PATCHES:
    raise newException(
      ValueError,
      &"fix_cowork_error_message: Only {patchesApplied}/{EXPECTED_PATCHES} patches applied",
    )

  # Verify brace balance
  let originalDelta = input.count('{') - input.count('}')
  let patchedDelta = result.count('{') - result.count('}')
  if originalDelta != patchedDelta:
    let diff = patchedDelta - originalDelta
    raise newException(
      ValueError,
      &"fix_cowork_error_message: Patch introduced brace imbalance: {diff:+} unmatched braces",
    )

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_cowork_error_message <file>"
    quit(1)
  let file = paramStr(1)
  echo "=== Patch: fix_cowork_error_message ==="
  echo &"  Target: {file}"
  if not fileExists(file):
    echo &"  [FAIL] File not found: {file}"
    quit(1)
  let input = readFile(file)
  let output = apply(input)
  if output == input:
    echo &"  [WARN] No changes made ({EXPECTED_PATCHES}/{EXPECTED_PATCHES} patterns matched but already applied)"
  else:
    writeFile(file, output)
    echo &"  [PASS] {EXPECTED_PATCHES} patches applied"
