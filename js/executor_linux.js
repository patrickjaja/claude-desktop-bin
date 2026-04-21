import { execFile as execFileCb, spawnSync } from 'node:child_process'
import { screen as electronScreen } from 'electron'
import { promisify } from 'node:util'

const execFile = promisify(execFileCb)

const DEFAULT_HOST_BUNDLE_ID = 'com.anthropic.claude-desktop'

const LINUX_CU_CAPABILITIES = {
  screenshotFiltering: 'native',
  platform: 'linux',
}

let sessionReadyPromise = null
let sessionStopPromise = null
let bridgeSessionActive = false
let exitHookInstalled = false
const legacyDisplayIdToElectronDisplayId = new Map()

const SYNTHETIC_INSTALLED_APPS = [
  {
    bundleId: 'plasmashell',
    displayName: 'Plasma Shell',
    path: '__synthetic__/plasmashell',
  },
]

const PLASMA_SHELL_BUNDLE_IDS = ['plasmashell', 'org.kde.plasmashell']

function debugLog(message, details) {
  if (details === undefined) {
    console.debug(`[linux-executor] ${message}`)
    return
  }
  console.debug(`[linux-executor] ${message}`, details)
}

function expandAllowedBundleIds(bundleIds) {
  const expanded = new Set(bundleIds || [])
  if (PLASMA_SHELL_BUNDLE_IDS.some(bundleId => expanded.has(bundleId))) {
    for (const bundleId of PLASMA_SHELL_BUNDLE_IDS) {
      expanded.add(bundleId)
    }
  }
  return [...expanded]
}

function buildBridgeCommand(command, args) {
  const envBin = process.env.KWIN_PORTAL_BRIDGE_BIN
  const spec = {
    command: envBin || 'kwin-portal-bridge',
    args: [command, ...args],
  }
  debugLog('bridge command prepared', spec)
  return spec
}

function roundedRect(rect) {
  return {
    x: Math.round(rect?.x ?? 0),
    y: Math.round(rect?.y ?? 0),
    width: Math.round(rect?.width ?? 0),
    height: Math.round(rect?.height ?? 0),
  }
}

function rectsEqual(a, b) {
  return (
    a.x === b.x &&
    a.y === b.y &&
    a.width === b.width &&
    a.height === b.height
  )
}

function electronDisplayForRustScreen(screen) {
  const rustGeometry = roundedRect(screen?.geometry)
  const displays = electronScreen.getAllDisplays()
  const exact = displays.find(display =>
    rectsEqual(roundedRect(display.bounds), rustGeometry),
  )
  if (exact) return exact

  try {
    return electronScreen.getDisplayNearestPoint({
      x: rustGeometry.x + Math.max(0, Math.floor(rustGeometry.width / 2)),
      y: rustGeometry.y + Math.max(0, Math.floor(rustGeometry.height / 2)),
    })
  } catch {
    return null
  }
}

function rememberDisplayIdMappings(displays) {
  for (const display of displays) {
    if (
      typeof display?._legacyDisplayId === 'number' &&
      typeof display?.displayId === 'number'
    ) {
      legacyDisplayIdToElectronDisplayId.set(
        display._legacyDisplayId,
        display.displayId,
      )
    }
  }
}

async function execBridge(command, args, opts = {}) {
  const spec = buildBridgeCommand(command, args)
  debugLog(`exec ${command}`, { args: spec.args })
  try {
    const { stdout } = await execFile(spec.command, spec.args, {
      encoding: 'utf8',
      windowsHide: true,
      maxBuffer: 16 * 1024 * 1024,
    })
    debugLog(`exec ${command} ok`, {
      stdoutLength: stdout.trim().length,
    })
    return stdout.trim()
  } catch (error) {
    const stderr = typeof error?.stderr === 'string' ? error.stderr.trim() : ''
    const stdout = typeof error?.stdout === 'string' ? error.stdout.trim() : ''
    const detail = stderr || stdout || error?.message || String(error)

    if (opts.allowAlreadyActive && /already active/i.test(detail)) {
      debugLog(`exec ${command} already active`, { detail })
      return ''
    }

    console.warn(`[linux-executor] exec ${command} failed`, {
      detail,
      args: spec.args,
    })
    throw new Error(`[kwin-portal-bridge] ${command} failed: ${detail}`)
  }
}

async function execBridgeJson(command, args, opts) {
  const stdout = await execBridge(command, args, opts)
  if (!stdout) return null
  const parsed = JSON.parse(stdout)
  debugLog(`exec ${command} parsed json`, {
    type: Array.isArray(parsed) ? 'array' : typeof parsed,
    length: Array.isArray(parsed) ? parsed.length : undefined,
  })
  return parsed
}

async function ensureBridgeSession() {
  if (!bridgeSessionActive) {
    throw new Error('[kwin-portal-bridge] bridge session is not active; cuLock is not held')
  }
  if (!sessionReadyPromise) {
    debugLog('starting bridge session')
    sessionReadyPromise = (async () => {
      await execBridge('session-start', [], { allowAlreadyActive: true })
    })().catch(error => {
      sessionReadyPromise = null
      console.warn('[linux-executor] bridge session startup failed', error)
      throw error
    })
  }
  return sessionReadyPromise
}

function installExitHook() {
  if (exitHookInstalled) return
  exitHookInstalled = true
  process.once('exit', () => {
    if (!bridgeSessionActive && !sessionReadyPromise) return
    const shutdownSpec = buildBridgeCommand('session-end', [])
    try {
      debugLog('stopping bridge session on process exit', shutdownSpec)
      spawnSync(shutdownSpec.command, shutdownSpec.args, {
        stdio: 'ignore',
        windowsHide: true,
      })
    } catch {}
  })
}

async function startBridgeSession() {
  installExitHook()
  bridgeSessionActive = true
  if (sessionStopPromise) {
    await sessionStopPromise
  }
  await ensureBridgeSession()
}

async function stopBridgeSession() {
  bridgeSessionActive = false
  if (sessionStopPromise) {
    return sessionStopPromise
  }
  if (!sessionReadyPromise) {
    debugLog('stopBridgeSession skipped; no active session promise')
    return
  }

  const readyPromise = sessionReadyPromise
  sessionReadyPromise = null
  sessionStopPromise = (async () => {
    try {
      await readyPromise
    } catch (error) {
      debugLog('stopBridgeSession after failed startup', {
        detail: error instanceof Error ? error.message : String(error),
      })
      return
    }
    debugLog('stopping bridge session')
    await execBridge('session-end', [])
  })().catch(error => {
    console.warn('[linux-executor] bridge session shutdown failed', error)
    throw error
  }).finally(() => {
    sessionStopPromise = null
  })

  return sessionStopPromise
}

function mapRustScreenToDisplay(screen, index) {
  const electronDisplay = electronDisplayForRustScreen(screen)
  const electronDisplayId =
    typeof electronDisplay?.id === 'number' ? electronDisplay.id : undefined
  return {
    displayId: electronDisplayId ?? index,
    width: screen.geometry.width,
    height: screen.geometry.height,
    scaleFactor:
      typeof screen.scale === 'number' && Number.isFinite(screen.scale)
        ? screen.scale
        : 1,
    originX: screen.geometry.x,
    originY: screen.geometry.y,
    isPrimary: !!screen.is_primary,
    label: screen.name || screen.id || `display-${index}`,
    _legacyDisplayId: index,
    _bridgeId: screen.id,
  }
}

async function getRustScreens() {
  const screens = await execBridgeJson('screens', [])
  if (!Array.isArray(screens) || screens.length === 0) {
    throw new Error('bridge returned no screens')
  }
  debugLog('loaded rust screens', {
    count: screens.length,
    ids: screens.map(screen => screen.id),
  })
  return screens
}

async function listDisplaysWithBridgeIds() {
  const screens = await getRustScreens()
  const displays = screens.map(mapRustScreenToDisplay)
  rememberDisplayIdMappings(displays)
  return displays
}

async function getDisplayByNumericId(displayId) {
  const displays = await listDisplaysWithBridgeIds()
  const selected =
    displays.find(display => display.displayId === displayId) ||
    displays.find(display => display._legacyDisplayId === displayId) ||
    displays.find(display => display.isPrimary) ||
    displays[0]

  if (!selected) {
    throw new Error('no displays enumerated')
  }

  debugLog('selected display', {
    requestedDisplayId: displayId,
    selectedDisplayId: selected.displayId,
    legacyDisplayId: selected._legacyDisplayId,
    bridgeId: selected._bridgeId,
    label: selected.label,
  })
  return selected
}

function screenshotResultFromRust(result, display) {
  const width = typeof result.width === 'number' ? result.width : 0
  const height = typeof result.height === 'number' ? result.height : 0
  return {
    base64: result.base64 || '',
    width,
    height,
    displayWidth:
      typeof result.displayWidth === 'number'
        ? result.displayWidth
        : display.width,
    displayHeight:
      typeof result.displayHeight === 'number'
        ? result.displayHeight
        : display.height,
    displayId: display.displayId,
    originX:
      typeof result.originX === 'number' ? result.originX : display.originX,
    originY:
      typeof result.originY === 'number' ? result.originY : display.originY,
  }
}

async function listWindows() {
  const windows = await execBridgeJson('windows', [])
  debugLog('loaded windows', {
    count: Array.isArray(windows) ? windows.length : 0,
  })
  return Array.isArray(windows) ? windows : []
}

function normalizeBundleIdFromWindow(window) {
  if (window?.transient === true && window?.transient_for) {
    const transientBundleId = normalizeBundleIdFromWindowRef(
      window.transient_for,
      new Set(typeof window.id === 'string' ? [window.id] : []),
    )
    if (transientBundleId) {
      return transientBundleId
    }
  }

  for (const candidate of [
    window.desktop_file_name,
    window.resource_class,
    window.resource_name,
    window.id,
  ]) {
    if (typeof candidate === 'string' && candidate.trim()) {
      return candidate.replace(/\.desktop$/i, '')
    }
  }
  return null
}

function normalizeBundleIdFromWindowRef(window, seenIds = new Set()) {
  if (!window || typeof window !== 'object') return null

  const windowId = typeof window.id === 'string' ? window.id : null
  if (windowId && seenIds.has(windowId)) {
    return null
  }

  const nextSeenIds = new Set(seenIds)
  if (windowId) {
    nextSeenIds.add(windowId)
  }

  if (window.transient === true && window.transient_for) {
    const transientBundleId = normalizeBundleIdFromWindowRef(
      window.transient_for,
      nextSeenIds,
    )
    if (transientBundleId) {
      return transientBundleId
    }
  }

  for (const candidate of [
    window.desktop_file_name,
    window.resource_class,
    window.resource_name,
    window.id,
  ]) {
    if (typeof candidate === 'string' && candidate.trim()) {
      return candidate.replace(/\.desktop$/i, '')
    }
  }

  return null
}

function displayNameFromWindow(window) {
  if (typeof window.title === 'string' && window.title.trim()) {
    return window.title
  }
  return normalizeBundleIdFromWindow(window) || window.id
}

function bundleIdMatches(window, bundleId) {
  const normalized = normalizeBundleIdFromWindow(window)
  if (typeof normalized === 'string' && normalized.toLowerCase() === bundleId.toLowerCase()) {
    return true
  }

  return (
    typeof window?.title === 'string' &&
    window.title.trim().toLowerCase() === bundleId.toLowerCase()
  )
}

function visibleForHitTest(window) {
  if (window.is_minimized === true) return false
  return window.is_visible !== false
}

function dockableWindow(window) {
  if (!visibleForHitTest(window)) return false
  if (window.is_dialog === true) return false
  return window.is_normal_window !== false
}

function topRightDockBounds(display) {
  const margin = 20
  const width = Math.max(240, Math.min(520, Math.round(display.width - margin)))
  const height = Math.max(240, Math.min(720, Math.round(display.height - margin)))
  return {
    x: Math.round(display.originX + display.width - width - margin),
    y: Math.round(display.originY + margin),
    width,
    height,
  }
}

async function resolveDisplayForWindow(window, mainWindow) {
  const displays = await listDisplaysWithBridgeIds()

  if (typeof window?.output === 'string') {
    const byBridgeId = displays.find(display => display._bridgeId === window.output)
    if (byBridgeId) {
      return byBridgeId
    }
  }

  try {
    if (mainWindow && !mainWindow.isDestroyed()) {
      const electronDisplay = electronScreen.getDisplayMatching(mainWindow.getBounds())
      const byElectronId = displays.find(display => display.displayId === electronDisplay.id)
      if (byElectronId) {
        return byElectronId
      }
    }
  } catch {}

  return displays.find(display => display.isPrimary) || displays[0]
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

function rectContains(rect, x, y) {
  return (
    rect &&
    rect.width > 0 &&
    rect.height > 0 &&
    x >= rect.x &&
    x < rect.x + rect.width &&
    y >= rect.y &&
    y < rect.y + rect.height
  )
}

function buttonFlag(button) {
  switch (button) {
    case 'left':
      return ['--button', 'left']
    case 'right':
      return ['--button', 'right']
    case 'middle':
      return ['--button', 'middle']
    default:
      throw new Error(`unsupported mouse button: ${button}`)
  }
}

function modifierFlags(modifiers) {
  const flags = []
  for (const modifier of modifiers || []) {
    flags.push('--modifier', modifier)
  }
  return flags
}

async function typeViaClipboard(backend, text) {
  let saved
  try {
    saved = await backend.readClipboard()
  } catch {}

  try {
    await backend.writeClipboard(text)
    await backend.key('ctrl+v')
  } finally {
    if (typeof saved === 'string') {
      try {
        await backend.writeClipboard(saved)
      } catch {}
    }
  }
}

function commandOutputToAppRef(result) {
  if (!result || typeof result !== 'object') return null
  if (typeof result.bundleId !== 'string' || typeof result.displayName !== 'string') {
    return null
  }
  return {
    bundleId: result.bundleId,
    displayName: result.displayName,
  }
}

function displayIdLookup(displays) {
  const byBridgeId = new Map()
  for (const display of displays) {
    byBridgeId.set(display._bridgeId, display.displayId)
  }
  return byBridgeId
}

function bridgeDisplayArg(display) {
  return display ? ['--display', display._bridgeId] : []
}

function teachPayloadArg(payload) {
  return ['--payload', JSON.stringify(payload || {})]
}

export function createRustLinuxBackend() {
  return {
    async prepareForAction(allowlistBundleIds, hostBundleId, displayId) {
      debugLog('prepareForAction', {
        allowlistBundleIds,
        hostBundleId,
        displayId,
      })
      const display = await getDisplayByNumericId(displayId)
      const args = [
        ...allowlistBundleIds.flatMap(id => ['--allowed-bundle-id', id]),
        '--host-bundle-id',
        hostBundleId,
        ...bridgeDisplayArg(display),
      ]
      const result = await execBridgeJson('prepare-for-action', args)
      debugLog('prepare-for-action result', result)
      return {
        hidden: Array.isArray(result?.hidden) ? result.hidden : [],
        activated: typeof result?.activated === 'string' ? result.activated : null,
      }
    },

    async previewHideSet(allowlistBundleIds, hostBundleId, displayId) {
      debugLog('previewHideSet', {
        allowlistBundleIds,
        hostBundleId,
        displayId,
      })
      const display = await getDisplayByNumericId(displayId)
      const args = [
        ...allowlistBundleIds.flatMap(id => ['--allowed-bundle-id', id]),
        '--host-bundle-id',
        hostBundleId,
        ...bridgeDisplayArg(display),
      ]
      const result = await execBridgeJson('preview-hide-set', args)
      debugLog('preview-hide-set result', {
        count: Array.isArray(result) ? result.length : 0,
      })
      return Array.isArray(result) ? result : []
    },

    async findWindowDisplays(bundleIds) {
      debugLog('findWindowDisplays', { bundleIds })
      const displays = await listDisplaysWithBridgeIds()
      const byBridgeId = displayIdLookup(displays)
      const windows = await listWindows()
      const displayMap = new Map()

      for (const bundleId of bundleIds) {
        displayMap.set(bundleId, new Set())
      }

      for (const window of windows) {
        const bundleId = normalizeBundleIdFromWindow(window)
        if (!bundleId || !displayMap.has(bundleId)) continue
        if (typeof window.output !== 'string') continue
        const numericDisplayId = byBridgeId.get(window.output)
        if (typeof numericDisplayId === 'number') {
          displayMap.get(bundleId).add(numericDisplayId)
        }
      }

      const resolved = bundleIds
        .map(bundleId => ({
          bundleId,
          displayIds: [...(displayMap.get(bundleId) || new Set())],
        }))
        .filter(item => item.displayIds.length > 0)
      debugLog('findWindowDisplays result', resolved)
      return resolved
    },

    async listDisplays() {
      const displays = await listDisplaysWithBridgeIds()
      debugLog('listDisplays', {
        count: displays.length,
        displays: displays.map(({ _bridgeId, ...display }) => display),
      })
      return displays.map(({ _bridgeId, ...display }) => display)
    },

    async getDisplaySize(displayId) {
      const { _bridgeId, ...display } = await getDisplayByNumericId(displayId)
      return display
    },

    async screenshot(displayId) {
      await ensureBridgeSession()
      const display = await getDisplayByNumericId(displayId)
      debugLog('screenshot', {
        displayId,
        bridgeDisplayId: display._bridgeId,
      })
      const result = await execBridgeJson('screenshot', bridgeDisplayArg(display))
      debugLog('screenshot result', {
        width: result?.width,
        height: result?.height,
        base64Length: result?.base64?.length,
      })
      return screenshotResultFromRust(result, display)
    },

    async zoom(region, displayId) {
      await ensureBridgeSession()
      const display = await getDisplayByNumericId(displayId)
      debugLog('zoom', {
        region,
        displayId,
        bridgeDisplayId: display._bridgeId,
      })
      const args = [
        ...bridgeDisplayArg(display),
        '--x',
        String(Math.round(region.x)),
        '--y',
        String(Math.round(region.y)),
        '--w',
        String(Math.round(region.w)),
        '--h',
        String(Math.round(region.h)),
      ]
      const result = await execBridgeJson('zoom', args)
      debugLog('zoom result', {
        width: result?.width,
        height: result?.height,
        base64Length: result?.base64?.length,
      })
      return {
        base64: result?.base64 || '',
        width: typeof result?.width === 'number' ? result.width : 0,
        height: typeof result?.height === 'number' ? result.height : 0,
      }
    },

    async key(keySequence, repeat) {
      await ensureBridgeSession()
      debugLog('key', { keySequence, repeat })
      const args = ['--keys', keySequence]
      if (typeof repeat === 'number') {
        args.push('--repeat', String(repeat))
      }
      await execBridgeJson('key-sequence', args)
    },

    async holdKey(keyNames, durationMs) {
      await ensureBridgeSession()
      debugLog('holdKey', { keyNames, durationMs })
      const args = [
        ...keyNames.flatMap(name => ['--key', name]),
        '--duration-ms',
        String(durationMs),
      ]
      await execBridgeJson('hold-key', args)
    },

    async type(text, opts) {
      debugLog('type', { textLength: text.length, viaClipboard: !!opts?.viaClipboard })
      if (opts?.viaClipboard) {
        await typeViaClipboard(this, text)
        return
      }
      await ensureBridgeSession()
      await execBridgeJson('type', ['--text', text])
    },

    async typePaced(text, delayMs) {
      debugLog('typePaced', { textLength: text.length, delayMs })
      await ensureBridgeSession()
      const args = ['--text', text]
      if (typeof delayMs === 'number' && Number.isFinite(delayMs)) {
        args.push('--delay-ms', String(Math.max(0, Math.round(delayMs))))
      }
      await execBridgeJson('type', args)
    },

    async readClipboard() {
      await ensureBridgeSession()
      const result = await execBridgeJson('read-clipboard', [])
      debugLog('readClipboard result', { textLength: result?.text?.length ?? 0 })
      return typeof result?.text === 'string' ? result.text : ''
    },

    async writeClipboard(text) {
      await ensureBridgeSession()
      debugLog('writeClipboard', { textLength: text.length })
      await execBridgeJson('write-clipboard', ['--text', text])
    },

    async moveMouse(x, y) {
      await ensureBridgeSession()
      debugLog('moveMouse', { x, y })
      await execBridgeJson('pointer-move', ['--x', String(Math.round(x)), '--y', String(Math.round(y))])
    },

    async click(x, y, button, count, modifiers) {
      await ensureBridgeSession()
      debugLog('click', { x, y, button, count, modifiers })
      const args = [
        '--x',
        String(Math.round(x)),
        '--y',
        String(Math.round(y)),
        ...buttonFlag(button),
        '--count',
        String(count),
        ...modifierFlags(modifiers),
      ]
      await execBridgeJson('pointer-click', args)
    },

    async mouseDown() {
      await ensureBridgeSession()
      debugLog('mouseDown')
      await execBridgeJson('left-mouse-down', [])
    },

    async mouseUp() {
      await ensureBridgeSession()
      debugLog('mouseUp')
      await execBridgeJson('left-mouse-up', [])
    },

    async getCursorPosition() {
      const result = await execBridgeJson('cursor-position', [])
      debugLog('getCursorPosition result', result)
      return {
        x: typeof result?.x === 'number' ? result.x : 0,
        y: typeof result?.y === 'number' ? result.y : 0,
      }
    },

    async drag(from, to) {
      await ensureBridgeSession()
      debugLog('drag', { from, to })
      const args = [
        '--from-x',
        String(Math.round(from?.x ?? 0)),
        '--from-y',
        String(Math.round(from?.y ?? 0)),
        '--to-x',
        String(Math.round(to.x)),
        '--to-y',
        String(Math.round(to.y)),
      ]
      if (from === undefined) {
        const current = await this.getCursorPosition()
        args[1] = String(Math.round(current.x))
        args[3] = String(Math.round(current.y))
      }
      await execBridgeJson('pointer-drag', args)
    },

    async scroll(x, y, dx, dy) {
      await ensureBridgeSession()
      debugLog('scroll', { x, y, dx, dy })
      await execBridgeJson('pointer-scroll', [
        '--x',
        String(Math.round(x)),
        '--y',
        String(Math.round(y)),
        '--dx',
        String(dx),
        '--dy',
        String(dy),
      ])
    },

    async getFrontmostApp() {
      const result = commandOutputToAppRef(await execBridgeJson('frontmost-app', []))
      debugLog('getFrontmostApp result', result)
      return result
    },

    async appUnderPoint(x, y) {
      const result = commandOutputToAppRef(
        await execBridgeJson('app-under-point', ['--x', String(Math.round(x)), '--y', String(Math.round(y))]),
      )
      debugLog('appUnderPoint result', { x, y, result })
      return result
    },

    async setWindowGeometry(windowId, geometry) {
      debugLog('setWindowGeometry', { windowId, geometry })
      return execBridgeJson('set-window-geometry', [
        '--window',
        windowId,
        '--x',
        String(Math.round(geometry.x)),
        '--y',
        String(Math.round(geometry.y)),
        '--width',
        String(Math.round(geometry.width)),
        '--height',
        String(Math.round(geometry.height)),
      ])
    },

    async setWindowKeepAbove(windowId, value) {
      debugLog('setWindowKeepAbove', { windowId, value })
      return execBridgeJson('set-window-keep-above', [
        '--window',
        windowId,
        '--value',
        value ? 'true' : 'false',
      ])
    },

    async activateWindow(windowId) {
      debugLog('activateWindow', { windowId })
      return execBridgeJson('activate-window', ['--window', windowId])
    },

    async showTeachStep(payload, displayId) {
      await ensureBridgeSession()
      let display
      if (typeof displayId === 'number') {
        display = await getDisplayByNumericId(displayId)
        debugLog('showTeachStep target display', {
          displayId,
          bridgeDisplayId: display._bridgeId,
          label: display.label,
        })
        await execBridgeJson('teach-display', ['--display', display._bridgeId])
      }
      const result = await execBridgeJson('teach-step', [
        ...teachPayloadArg(payload),
        ...bridgeDisplayArg(display),
      ])
      debugLog('showTeachStep result', result)
      return result
    },

    async setTeachWorking() {
      await ensureBridgeSession()
      debugLog('setTeachWorking')
      await execBridgeJson('teach-working', [])
    },

    async hideTeachOverlay() {
      await ensureBridgeSession()
      debugLog('hideTeachOverlay')
      await execBridgeJson('teach-hide', [])
    },

    async setTeachDisplay(displayId) {
      await ensureBridgeSession()
      const display = await getDisplayByNumericId(displayId)
      debugLog('setTeachDisplay', {
        displayId,
        bridgeDisplayId: display._bridgeId,
      })
      await execBridgeJson('teach-display', ['--display', display._bridgeId])
    },

    async waitTeachEvent() {
      await ensureBridgeSession()
      const result = await execBridgeJson('teach-wait-event', [])
      debugLog('waitTeachEvent result', result)
      return result
    },

    async setSessionOverlayDisplay(displayId) {
      await ensureBridgeSession()
      let display = null

      if (typeof displayId === 'number') {
        display = await getDisplayByNumericId(displayId)
      } else {
        const displays = await listDisplaysWithBridgeIds()
        display = displays.find(candidate => candidate.isPrimary) || displays[0] || null
      }

      if (!display) {
        debugLog('setSessionOverlayDisplay', { displayId: null, bridgeDisplayId: null })
        await execBridgeJson('set-overlay-display', [])
        return
      }

      debugLog('setSessionOverlayDisplay', {
        displayId: typeof displayId === 'number' ? displayId : null,
        bridgeDisplayId: display._bridgeId,
      })
      await execBridgeJson('set-overlay-display', ['--display', display._bridgeId])
    },

    async listInstalledApps() {
      const result = await execBridgeJson('list-installed-apps', [])
      const apps = Array.isArray(result) ? [...result, ...SYNTHETIC_INSTALLED_APPS] : [...SYNTHETIC_INSTALLED_APPS]
      debugLog('listInstalledApps result', {
        count: apps.length,
      })
      return apps
    },

    async getAppIcon(target) {
      const result = await execBridgeJson('get-app-icon', ['--target', target])
      debugLog('getAppIcon result', {
        target,
        found: typeof result === 'string',
        length: typeof result === 'string' ? result.length : 0,
      })
      return typeof result === 'string' ? result : undefined
    },

    async listRunningApps() {
      const windows = await listWindows()
      const byBundleId = new Map()
      for (const window of windows) {
        if (!visibleForHitTest(window)) continue
        const bundleId = normalizeBundleIdFromWindow(window)
        if (!bundleId || byBundleId.has(bundleId)) continue
        byBundleId.set(bundleId, {
          bundleId,
          displayName: displayNameFromWindow(window),
          pid: typeof window.pid === 'number' ? window.pid : undefined,
        })
      }
      const apps = [...byBundleId.values()]
      debugLog('listRunningApps result', { count: apps.length, apps })
      return apps
    },

    async openApp(bundleId) {
      debugLog('openApp', { bundleId })
      await execBridgeJson('open-app', ['--app', bundleId])
    },

    async unhideApps() {
      debugLog('unhideApps')
      await execBridgeJson('restore-prepare-state', [])
    },
  }
}

function toScreenshotResult(capture, display) {
  return {
    base64: capture.base64,
    width: capture.width,
    height: capture.height,
    displayWidth: display.width,
    displayHeight: display.height,
    displayId: display.displayId,
    originX: display.originX,
    originY: display.originY,
  }
}

async function getDisplaySize(backend, displayId) {
  if (typeof backend.getDisplaySize === 'function') {
    return backend.getDisplaySize(displayId)
  }
  const displays = await backend.listDisplays()
  return (
    displays.find(display => display.displayId === displayId) ||
    displays.find(display => display.isPrimary) ||
    displays[0]
  )
}

export function createLinuxExecutor(opts = {}) {
  const backend = opts.backend || createRustLinuxBackend()
  const hostBundleId = opts.hostBundleId || DEFAULT_HOST_BUNDLE_ID
  debugLog('createLinuxExecutor', { hostBundleId })

  const teachControllerState = {
    initialized: false,
    activeSessionId: null,
    mainWindowHidden: false,
    watcherGeneration: 0,
  }

  const sessionOverlayState = {
    manager: null,
  }

  const dockControllerState = {
    initialized: false,
    isLockHeld: false,
    holder: null,
    mainWindow: null,
    restore: null,
    operationGeneration: 0,
  }

  async function findHostMainWindow() {
    const windows = await listWindows()
    const matches = windows
      .filter(window => dockableWindow(window) && bundleIdMatches(window, hostBundleId))
      .sort((a, b) => {
        const activeDelta = Number(!!b.is_active) - Number(!!a.is_active)
        if (activeDelta !== 0) return activeDelta
        return (b.stacking_order ?? 0) - (a.stacking_order ?? 0)
      })

    const selected = matches[0] || null
    debugLog('findHostMainWindow', {
      hostBundleId,
      found: !!selected,
      windowId: selected?.id,
      title: selected?.title,
      output: selected?.output,
    })
    return selected
  }

  async function resolveRestoreWindow(restore, mainWindow) {
    const windows = await listWindows()
    const exact = windows.find(window => window.id === restore.windowId)
    if (exact) {
      debugLog('resolveRestoreWindow matched saved window id', {
        windowId: exact.id,
      })
      return exact
    }

    try {
      if (mainWindow && !mainWindow.isDestroyed()) {
        if (!mainWindow.isVisible()) {
          mainWindow.show()
        }
        mainWindow.focus()
      }
    } catch (error) {
      console.warn('[linux-executor] failed to show Claude window before restore', error)
    }

    for (let attempt = 0; attempt < 10; attempt += 1) {
      const candidate = await findHostMainWindow()
      if (candidate) {
        debugLog('resolveRestoreWindow matched current host window', {
          savedWindowId: restore.windowId,
          targetWindowId: candidate.id,
          attempt,
        })
        return candidate
      }
      await sleep(100)
    }

    debugLog('resolveRestoreWindow failed to locate current host window', {
      savedWindowId: restore.windowId,
    })
    return null
  }

  async function dockClaudeWindow() {
    const generation = ++dockControllerState.operationGeneration
    const mainWindow = dockControllerState.mainWindow
    let window = await findHostMainWindow()

    if (!window) {
      debugLog('dockClaudeWindow skipped; no host window found')
      return
    }

    if (!dockControllerState.restore) {
      dockControllerState.restore = {
        windowId: window.id,
        bounds: roundedRect(window.geometry),
        keepAbove: !!window.keep_above,
        wasMaximized:
          typeof mainWindow?.isMaximized === 'function' ? mainWindow.isMaximized() : false,
        wasFullScreen:
          typeof mainWindow?.isFullScreen === 'function' ? mainWindow.isFullScreen() : false,
      }
    }

    if (mainWindow && !mainWindow.isDestroyed()) {
      if (dockControllerState.restore.wasFullScreen) {
        await new Promise(resolve => {
          mainWindow.once('leave-full-screen', resolve)
          mainWindow.setFullScreen(false)
        }).catch(() => {})
      }

      if (dockControllerState.restore.wasMaximized) {
        try {
          mainWindow.unmaximize()
        } catch {}
      }

      if (dockControllerState.restore.wasFullScreen || dockControllerState.restore.wasMaximized) {
        await sleep(150)
        window = (await findHostMainWindow()) || window
        dockControllerState.restore.windowId = window.id
        dockControllerState.restore.bounds = roundedRect(window.geometry)
      }
    }

    if (dockControllerState.operationGeneration !== generation || !dockControllerState.isLockHeld) {
      return
    }

    const display = await resolveDisplayForWindow(window, mainWindow)
    if (!display) {
      debugLog('dockClaudeWindow skipped; no display resolved')
      return
    }

    const targetBounds = topRightDockBounds(display)
    await backend.setWindowGeometry(window.id, targetBounds)
    await backend.setWindowKeepAbove(window.id, true)
    debugLog('dockClaudeWindow applied', {
      windowId: window.id,
      targetBounds,
      displayId: display.displayId,
      bridgeDisplayId: display._bridgeId,
    })
  }

  async function restoreClaudeWindow() {
    const generation = ++dockControllerState.operationGeneration
    const restore = dockControllerState.restore
    const mainWindow = dockControllerState.mainWindow

    if (!restore) {
      debugLog('restoreClaudeWindow skipped; no restore state')
      return
    }

    dockControllerState.restore = null

    let targetWindow = null
    let restoredThroughBridge = false

    try {
      targetWindow = await resolveRestoreWindow(restore, mainWindow)
      if (targetWindow) {
        await backend.setWindowGeometry(targetWindow.id, restore.bounds)
        await backend.setWindowKeepAbove(targetWindow.id, restore.keepAbove)
        await backend.activateWindow(targetWindow.id)
        restoredThroughBridge = true
      }
    } catch (error) {
      console.warn('[linux-executor] failed to restore Claude window through bridge', error)
    }

    if (dockControllerState.operationGeneration !== generation) {
      return
    }

    if (mainWindow && !mainWindow.isDestroyed()) {
      try {
        mainWindow.show()
        mainWindow.focus()
      } catch {}
      if (restore.wasMaximized) {
        try {
          mainWindow.maximize()
        } catch {}
      }
      if (restore.wasFullScreen) {
        try {
          mainWindow.setFullScreen(true)
        } catch {}
      }
    }

    debugLog('restoreClaudeWindow applied', {
      savedWindowId: restore.windowId,
      targetWindowId: targetWindow?.id ?? null,
      restoreBounds: restore.bounds,
      restoredThroughBridge,
    })
  }

  function resolveTeachDisplayId(manager, mainWindow, sessionId) {
    const session = typeof manager?.getSession === 'function' ? manager.getSession(sessionId) : null
    if (typeof session?.cuSelectedDisplayId === 'number') {
      return session.cuSelectedDisplayId
    }

    try {
      if (mainWindow && !mainWindow.isDestroyed()) {
        return electronScreen.getDisplayMatching(mainWindow.getBounds()).id
      }
    } catch {}

    return undefined
  }

  function resolveSessionOverlayDisplayId(manager, sessionId) {
    const targetSessionId =
      sessionId ??
      (typeof manager?.getCuLockHolder === 'function' ? manager.getCuLockHolder() : null)

    if (targetSessionId && typeof manager?.getSession === 'function') {
      const session = manager.getSession(targetSessionId)
      if (typeof session?.cuSelectedDisplayId === 'number') {
        return session.cuSelectedDisplayId
      }
    }

    return undefined
  }

  function restoreTeachMainWindow(mainWindow) {
    if (!teachControllerState.mainWindowHidden) return
    teachControllerState.mainWindowHidden = false
    try {
      if (mainWindow && !mainWindow.isDestroyed()) {
        if (!mainWindow.isVisible()) {
          mainWindow.show()
        }
      }
    } catch (error) {
      console.warn('[linux-executor] failed to restore teach main window', error)
    }
  }

  async function stopTeachSession(manager, mainWindow) {
    const holder = typeof manager?.getCuLockHolder === 'function' ? manager.getCuLockHolder() : null

    if (holder) {
      debugLog('stopTeachSession', { holder })
      await manager.stopSession(holder)
      return
    }

    debugLog('stopTeachSession fallback without holder')
    await backend.hideTeachOverlay().catch(error => {
      console.warn('[linux-executor] failed to hide teach overlay during fallback stop', error)
    })
    restoreTeachMainWindow(mainWindow)
  }

  function startTeachEventWatcher(manager, mainWindow, sessionId) {
    const generation = ++teachControllerState.watcherGeneration

    ;(async () => {
      while (
        teachControllerState.activeSessionId === sessionId &&
        teachControllerState.watcherGeneration === generation
      ) {
        const event = await backend.waitTeachEvent()

        if (
          teachControllerState.activeSessionId !== sessionId ||
          teachControllerState.watcherGeneration !== generation
        ) {
          return
        }

        if (event?.action === 'exit') {
          await stopTeachSession(manager, mainWindow)
          return
        }

        if (event?.action === 'hidden') {
          return
        }
      }
    })().catch(error => {
      console.warn('[linux-executor] teach event watcher failed', error)
    })
  }

  return {
    capabilities: {
      ...LINUX_CU_CAPABILITIES,
      hostBundleId,
    },

    async __setLockHeld(isHeld) {
      debugLog('__setLockHeld', { isHeld })
      dockControllerState.isLockHeld = isHeld
      if (isHeld) {
        await startBridgeSession()
        const displayId = resolveSessionOverlayDisplayId(
          sessionOverlayState.manager,
        )
        await backend.setSessionOverlayDisplay(displayId).catch(error => {
          console.warn('[linux-executor] failed to set session overlay display on lock acquire', error)
        })
        if (dockControllerState.initialized) {
          await dockClaudeWindow()
        }
      } else {
        if (dockControllerState.initialized) {
          await restoreClaudeWindow()
        }
        await stopBridgeSession()
      }
    },

    __normalizeDisplayId(displayId) {
      const normalized =
        legacyDisplayIdToElectronDisplayId.get(displayId) ?? displayId
      debugLog('__normalizeDisplayId', { input: displayId, normalized })
      return normalized
    },

    __initDockController(mainWindow) {
      if (dockControllerState.initialized) return
      dockControllerState.initialized = true
      dockControllerState.mainWindow = mainWindow

      if (dockControllerState.isLockHeld) {
        const displayId = resolveSessionOverlayDisplayId(
          sessionOverlayState.manager,
        )
        backend.setSessionOverlayDisplay(displayId).catch(error => {
          console.warn('[linux-executor] failed to set session overlay display on dock init', error)
        })
        dockClaudeWindow().catch(error => {
          console.warn('[linux-executor] failed to dock Claude window on init', error)
        })
      }

      debugLog('__initDockController installed')
    },

    __initTeachController(manager, mainWindow) {
      if (teachControllerState.initialized) return
      teachControllerState.initialized = true
      sessionOverlayState.manager = manager

      if (dockControllerState.isLockHeld) {
        const displayId = resolveSessionOverlayDisplayId(manager)
        backend.setSessionOverlayDisplay(displayId).catch(error => {
          console.warn('[linux-executor] failed to sync session overlay display on controller init', error)
        })
      }

      manager.on('teachModeChanged', ({ sessionId, active }) => {
        if (active) {
          teachControllerState.activeSessionId = sessionId

          const displayId = resolveTeachDisplayId(manager, mainWindow, sessionId)
          if (typeof displayId === 'number') {
            backend.setTeachDisplay(displayId).catch(error => {
              console.warn('[linux-executor] failed to set initial teach display', error)
            })
          }

          try {
            if (mainWindow && !mainWindow.isDestroyed() && mainWindow.isVisible()) {
              mainWindow.hide()
              teachControllerState.mainWindowHidden = true
            }
          } catch (error) {
            console.warn('[linux-executor] failed to hide teach main window', error)
          }

          startTeachEventWatcher(manager, mainWindow, sessionId)
          return
        }

        teachControllerState.activeSessionId = null
        teachControllerState.watcherGeneration += 1
        backend.hideTeachOverlay().catch(error => {
          console.warn('[linux-executor] failed to hide teach overlay on deactivate', error)
        })
        restoreTeachMainWindow(mainWindow)
      })

      manager.on('teachStepRequested', ({ sessionId, payload }) => {
        const targetSessionId = sessionId ?? teachControllerState.activeSessionId
        const displayId = resolveTeachDisplayId(manager, mainWindow, targetSessionId)

        backend
          .showTeachStep(payload, displayId)
          .then(async result => {
            if (result?.action === 'exit') {
              manager.resolveTeachStep({ action: 'exit' })
              await stopTeachSession(manager, mainWindow)
              return
            }

            manager.resolveTeachStep({ action: 'next' })
          })
          .catch(async error => {
            console.warn('[linux-executor] showTeachStep failed', error)
            manager.resolveTeachStep({ action: 'exit' })
            await stopTeachSession(manager, mainWindow)
          })
      })

      manager.on('teachStepWorking', () => {
        backend.setTeachWorking().catch(error => {
          console.warn('[linux-executor] failed to switch teach overlay to working', error)
        })
      })

      manager.on('cuSelectedDisplayChanged', ({ sessionId, displayId }) => {
        const holder =
          typeof manager?.getCuLockHolder === 'function' ? manager.getCuLockHolder() : null
        if (dockControllerState.isLockHeld && holder === sessionId) {
          const resolvedDisplayId = resolveSessionOverlayDisplayId(
            manager,
            sessionId,
          )
          backend.setSessionOverlayDisplay(resolvedDisplayId).catch(error => {
            console.warn('[linux-executor] failed to retarget session overlay display', error)
          })
        }

        if (sessionId !== teachControllerState.activeSessionId) return
        backend.setTeachDisplay(displayId).catch(error => {
          console.warn('[linux-executor] failed to retarget teach overlay display', error)
        })
      })

      manager.on('lifecycleChanged', ({ sessionId, newState }) => {
        if (sessionId !== teachControllerState.activeSessionId || newState === 'running') {
          return
        }

        teachControllerState.activeSessionId = null
        teachControllerState.watcherGeneration += 1
        backend.hideTeachOverlay().catch(error => {
          console.warn('[linux-executor] failed to hide teach overlay during lifecycle fallback', error)
        })
        restoreTeachMainWindow(mainWindow)
      })

      debugLog('__initTeachController installed')
    },

    async prepareForAction(allowlistBundleIds, displayId) {
      const expandedAllowlistBundleIds = expandAllowedBundleIds(allowlistBundleIds)
      const result = await backend.prepareForAction(
        expandedAllowlistBundleIds,
        hostBundleId,
        displayId,
      )
      return result.hidden
    },

    async previewHideSet(allowlistBundleIds, displayId) {
      return backend.previewHideSet(
        expandAllowedBundleIds(allowlistBundleIds),
        hostBundleId,
        displayId,
      )
    },

    async findWindowDisplays(bundleIds) {
      return backend.findWindowDisplays(bundleIds)
    },

    async getDisplaySize(displayId) {
      return getDisplaySize(backend, displayId)
    },

    async listDisplays() {
      return backend.listDisplays()
    },

    async resolvePrepareCapture(opts) {
      let hidden = []
      let activated = null

      if (opts.doHide ?? true) {
        const expandedAllowedBundleIds = expandAllowedBundleIds(opts.allowedBundleIds)
        const result = await backend.prepareForAction(
          expandedAllowedBundleIds,
          hostBundleId,
          opts.preferredDisplayId,
        )
        hidden = result.hidden
        activated = result.activated
      }

      try {
        const display = await getDisplaySize(backend, opts.preferredDisplayId)
        const result = await backend.screenshot(opts.preferredDisplayId)

        return {
          ...toScreenshotResult(result, display),
          hidden,
          activated,
        }
      } catch (error) {
        const display = await getDisplaySize(backend, opts.preferredDisplayId)
        return {
          base64: '',
          width: 0,
          height: 0,
          displayWidth: display?.width ?? 0,
          displayHeight: display?.height ?? 0,
          displayId: display?.displayId ?? opts.preferredDisplayId ?? 0,
          originX: display?.originX ?? 0,
          originY: display?.originY ?? 0,
          hidden,
          activated,
          captureError:
            error instanceof Error ? error.message : 'Screenshot capture failed',
        }
      }
    },

    async screenshot(opts) {
      const display = await getDisplaySize(backend, opts.displayId)
      return toScreenshotResult(await backend.screenshot(opts.displayId), display)
    },

    async zoom(regionLogical, allowedBundleIds, displayId) {
      void allowedBundleIds
      return backend.zoom(regionLogical, displayId)
    },

    async key(keySequence, repeat) {
      await backend.key(keySequence, repeat)
    },

    async holdKey(keyNames, durationMs) {
      await backend.holdKey(keyNames, durationMs)
    },

    async type(text, opts) {
      await backend.type(text, opts)
    },

    async typePaced(text, delayMs) {
      await backend.typePaced(text, delayMs)
    },

    readClipboard() {
      return backend.readClipboard()
    },

    writeClipboard(text) {
      return backend.writeClipboard(text)
    },

    async moveMouse(x, y) {
      await backend.moveMouse(x, y)
    },

    async click(x, y, button, count, modifiers) {
      await backend.click(x, y, button, count, modifiers)
    },

    async mouseDown() {
      await backend.mouseDown()
    },

    async mouseUp() {
      await backend.mouseUp()
    },

    async getCursorPosition() {
      return backend.getCursorPosition()
    },

    async drag(from, to) {
      await backend.drag(from, to)
    },

    async scroll(x, y, dx, dy) {
      await backend.scroll(x, y, dx, dy)
    },

    async getFrontmostApp() {
      return backend.getFrontmostApp()
    },

    async appUnderPoint(x, y) {
      return backend.appUnderPoint(x, y)
    },

    async listInstalledApps() {
      return backend.listInstalledApps()
    },

    async getAppIcon(path) {
      return backend.getAppIcon(path)
    },

    async listRunningApps() {
      return backend.listRunningApps()
    },

    async openApp(bundleId) {
      await backend.openApp(bundleId)
    },
  }
}

export async function unhideComputerUseAppsLinux(
  bundleIds,
  backend = createRustLinuxBackend(),
) {
  if (!bundleIds || bundleIds.length === 0) return
  await backend.unhideApps(bundleIds)
}
