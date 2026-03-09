// @patch-target: app.asar.contents/computer-use-server.js
// @patch-type: replace
/**
 * Linux Computer Use MCP Server
 *
 * Provides desktop automation tools (screenshot, click, type, scroll, key)
 * using xdotool (input) and scrot (screenshots) on X11.
 *
 * Registered as an internal MCP server named "computer-use" so the model
 * can call mcp__computer-use__* tools.
 *
 * Protocol: JSON-RPC over stdio (MCP standard).
 */

const { execSync, exec } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

// ── Screen info ──────────────────────────────────────────────────────────────

function getScreenSize() {
  try {
    const out = execSync('xdpyinfo 2>/dev/null | grep dimensions', { encoding: 'utf-8' });
    const m = out.match(/(\d+)x(\d+)/);
    if (m) return { width: parseInt(m[1]), height: parseInt(m[2]) };
  } catch {}
  return { width: 1920, height: 1080 };
}

const SCREEN = getScreenSize();

// ── Tool implementations ─────────────────────────────────────────────────────

function screenshot() {
  const tmp = path.join(os.tmpdir(), `claude-cu-${Date.now()}.png`);
  try {
    execSync(`scrot -o "${tmp}"`, { timeout: 10000 });
    const buf = fs.readFileSync(tmp);
    fs.unlinkSync(tmp);
    return {
      type: 'image',
      source: { type: 'base64', media_type: 'image/png', data: buf.toString('base64') }
    };
  } catch (e) {
    // Fallback to import (ImageMagick)
    try {
      execSync(`import -window root "${tmp}"`, { timeout: 10000 });
      const buf = fs.readFileSync(tmp);
      fs.unlinkSync(tmp);
      return {
        type: 'image',
        source: { type: 'base64', media_type: 'image/png', data: buf.toString('base64') }
      };
    } catch (e2) {
      return { type: 'text', text: `Screenshot failed: ${e2.message}` };
    }
  }
}

function zoom(coordinate, size) {
  const tmp = path.join(os.tmpdir(), `claude-cu-zoom-${Date.now()}.png`);
  const [x, y] = coordinate;
  const half = Math.floor((size || 400) / 2);
  const gx = Math.max(0, x - half);
  const gy = Math.max(0, y - half);
  try {
    execSync(`import -window root -crop ${size||400}x${size||400}+${gx}+${gy} "${tmp}"`, { timeout: 10000 });
    const buf = fs.readFileSync(tmp);
    fs.unlinkSync(tmp);
    return {
      type: 'image',
      source: { type: 'base64', media_type: 'image/png', data: buf.toString('base64') }
    };
  } catch (e) {
    return { type: 'text', text: `Zoom failed: ${e.message}` };
  }
}

function moveMouse(x, y) {
  execSync(`xdotool mousemove ${x} ${y}`);
}

function leftClick(x, y) {
  if (x !== undefined && y !== undefined) moveMouse(x, y);
  execSync('xdotool click 1');
  return { type: 'text', text: `Left clicked at (${x}, ${y})` };
}

function rightClick(x, y) {
  if (x !== undefined && y !== undefined) moveMouse(x, y);
  execSync('xdotool click 3');
  return { type: 'text', text: `Right clicked at (${x}, ${y})` };
}

function doubleClick(x, y) {
  if (x !== undefined && y !== undefined) moveMouse(x, y);
  execSync('xdotool click --repeat 2 --delay 50 1');
  return { type: 'text', text: `Double clicked at (${x}, ${y})` };
}

function tripleClick(x, y) {
  if (x !== undefined && y !== undefined) moveMouse(x, y);
  execSync('xdotool click --repeat 3 --delay 50 1');
  return { type: 'text', text: `Triple clicked at (${x}, ${y})` };
}

function middleClick(x, y) {
  if (x !== undefined && y !== undefined) moveMouse(x, y);
  execSync('xdotool click 2');
  return { type: 'text', text: `Middle clicked at (${x}, ${y})` };
}

function typeText(text) {
  // xdotool type has issues with special chars, use xdotool key for those
  execSync(`xdotool type --clearmodifiers -- ${JSON.stringify(text)}`);
  return { type: 'text', text: `Typed: ${text.substring(0, 50)}${text.length > 50 ? '...' : ''}` };
}

function pressKey(key) {
  // Map common key names to xdotool names
  const keyMap = {
    'Return': 'Return', 'Enter': 'Return',
    'Tab': 'Tab', 'Escape': 'Escape', 'space': 'space',
    'BackSpace': 'BackSpace', 'Delete': 'Delete',
    'Up': 'Up', 'Down': 'Down', 'Left': 'Left', 'Right': 'Right',
    'Home': 'Home', 'End': 'End', 'Page_Up': 'Page_Up', 'Page_Down': 'Page_Down',
    'F1': 'F1', 'F2': 'F2', 'F3': 'F3', 'F4': 'F4', 'F5': 'F5',
    'F6': 'F6', 'F7': 'F7', 'F8': 'F8', 'F9': 'F9', 'F10': 'F10',
    'F11': 'F11', 'F12': 'F12',
  };
  // Handle modifier combos like "ctrl+c", "alt+F4"
  const mapped = key.split('+').map(k => {
    const trimmed = k.trim();
    const lower = trimmed.toLowerCase();
    if (lower === 'ctrl' || lower === 'control') return 'ctrl';
    if (lower === 'alt') return 'alt';
    if (lower === 'shift') return 'shift';
    if (lower === 'super' || lower === 'meta' || lower === 'cmd') return 'super';
    return keyMap[trimmed] || trimmed;
  }).join('+');
  execSync(`xdotool key --clearmodifiers ${mapped}`);
  return { type: 'text', text: `Pressed key: ${key}` };
}

function scroll(x, y, direction, amount) {
  if (x !== undefined && y !== undefined) moveMouse(x, y);
  const clicks = amount || 3;
  const btn = { up: 4, down: 5, left: 6, right: 7 }[direction] || 5;
  execSync(`xdotool click --repeat ${clicks} --delay 30 ${btn}`);
  return { type: 'text', text: `Scrolled ${direction} ${clicks} clicks at (${x}, ${y})` };
}

function leftClickDrag(startX, startY, endX, endY) {
  moveMouse(startX, startY);
  execSync('xdotool mousedown 1');
  // Smooth drag
  execSync(`xdotool mousemove --sync ${endX} ${endY}`);
  execSync('xdotool mouseup 1');
  return { type: 'text', text: `Dragged from (${startX},${startY}) to (${endX},${endY})` };
}

function hover(x, y) {
  moveMouse(x, y);
  return { type: 'text', text: `Moved cursor to (${x}, ${y})` };
}

function wait(seconds) {
  execSync(`sleep ${Math.min(seconds || 1, 30)}`);
  return { type: 'text', text: `Waited ${seconds} seconds` };
}

function getCursorPosition() {
  try {
    const out = execSync('xdotool getmouselocation', { encoding: 'utf-8' });
    const m = out.match(/x:(\d+)\s+y:(\d+)/);
    if (m) return { type: 'text', text: `Cursor at (${m[1]}, ${m[2]})` };
  } catch {}
  return { type: 'text', text: 'Could not get cursor position' };
}

// ── Tool dispatch ────────────────────────────────────────────────────────────

function handleAction(params) {
  const { action, coordinate, text, start_coordinate, duration, scroll_direction, scroll_amount, size } = params;

  switch (action) {
    case 'screenshot':
      return screenshot();
    case 'zoom':
      return zoom(coordinate || [SCREEN.width/2, SCREEN.height/2], size || 400);
    case 'left_click':
      return leftClick(coordinate?.[0], coordinate?.[1]);
    case 'right_click':
      return rightClick(coordinate?.[0], coordinate?.[1]);
    case 'double_click':
      return doubleClick(coordinate?.[0], coordinate?.[1]);
    case 'triple_click':
      return tripleClick(coordinate?.[0], coordinate?.[1]);
    case 'middle_click':
      return middleClick(coordinate?.[0], coordinate?.[1]);
    case 'type':
      return typeText(text || '');
    case 'key':
      return pressKey(text || '');
    case 'scroll':
      return scroll(coordinate?.[0], coordinate?.[1], scroll_direction || 'down', scroll_amount || 3);
    case 'left_click_drag':
      return leftClickDrag(
        start_coordinate?.[0] || coordinate?.[0], start_coordinate?.[1] || coordinate?.[1],
        coordinate?.[0], coordinate?.[1]
      );
    case 'hover':
      return hover(coordinate?.[0], coordinate?.[1]);
    case 'wait':
      return wait(duration || 1);
    case 'cursor_position':
      return getCursorPosition();
    default:
      return { type: 'text', text: `Unknown action: ${action}` };
  }
}

// ── MCP Server (JSON-RPC over stdio) ─────────────────────────────────────────

const SERVER_INFO = {
  name: 'computer-use',
  version: '1.0.0',
};

const TOOLS = [{
  name: 'computer',
  description: `Use mouse and keyboard to interact with the Linux desktop, and take screenshots.\n\nScreen size: ${SCREEN.width}x${SCREEN.height}\n\nActions: screenshot, left_click, right_click, double_click, triple_click, middle_click, type, key, scroll, left_click_drag, hover, wait, zoom, cursor_position`,
  inputSchema: {
    type: 'object',
    properties: {
      action: {
        type: 'string',
        enum: ['left_click', 'right_click', 'type', 'screenshot', 'wait', 'scroll', 'key',
               'left_click_drag', 'double_click', 'triple_click', 'middle_click', 'zoom',
               'hover', 'cursor_position'],
        description: 'The action to perform'
      },
      coordinate: {
        type: 'array', items: { type: 'integer' },
        description: '[x, y] pixel coordinates for click/scroll/drag target'
      },
      start_coordinate: {
        type: 'array', items: { type: 'integer' },
        description: '[x, y] start coordinates for drag actions'
      },
      text: {
        type: 'string',
        description: 'Text to type, or key combo to press (e.g. "ctrl+c")'
      },
      scroll_direction: {
        type: 'string', enum: ['up', 'down', 'left', 'right'],
        description: 'Scroll direction'
      },
      scroll_amount: {
        type: 'integer',
        description: 'Number of scroll clicks (default 3)'
      },
      duration: {
        type: 'number',
        description: 'Seconds to wait (for wait action)'
      },
      size: {
        type: 'integer',
        description: 'Size in pixels for zoom region (default 400)'
      }
    },
    required: ['action']
  }
}];

let requestId = 0;
let buffer = '';

function sendResponse(id, result) {
  const msg = JSON.stringify({ jsonrpc: '2.0', id, result });
  const header = `Content-Length: ${Buffer.byteLength(msg)}\r\n\r\n`;
  process.stdout.write(header + msg);
}

function sendError(id, code, message) {
  const msg = JSON.stringify({ jsonrpc: '2.0', id, error: { code, message } });
  const header = `Content-Length: ${Buffer.byteLength(msg)}\r\n\r\n`;
  process.stdout.write(header + msg);
}

function sendNotification(method, params) {
  const msg = JSON.stringify({ jsonrpc: '2.0', method, params });
  const header = `Content-Length: ${Buffer.byteLength(msg)}\r\n\r\n`;
  process.stdout.write(header + msg);
}

function handleRequest(req) {
  switch (req.method) {
    case 'initialize':
      return sendResponse(req.id, {
        protocolVersion: '2024-11-05',
        capabilities: { tools: {} },
        serverInfo: SERVER_INFO
      });

    case 'notifications/initialized':
      // No response needed for notifications
      return;

    case 'tools/list':
      return sendResponse(req.id, { tools: TOOLS });

    case 'tools/call': {
      const { name, arguments: args } = req.params;
      if (name !== 'computer') {
        return sendError(req.id, -32601, `Unknown tool: ${name}`);
      }
      try {
        const result = handleAction(args || {});
        const content = Array.isArray(result) ? result : [result];
        return sendResponse(req.id, { content, isError: false });
      } catch (e) {
        return sendResponse(req.id, {
          content: [{ type: 'text', text: `Error: ${e.message}` }],
          isError: true
        });
      }
    }

    case 'ping':
      return sendResponse(req.id, {});

    default:
      if (req.id !== undefined) {
        return sendError(req.id, -32601, `Method not found: ${req.method}`);
      }
  }
}

// Parse Content-Length framed JSON-RPC messages
process.stdin.setEncoding('utf-8');
process.stdin.on('data', (chunk) => {
  buffer += chunk;
  while (true) {
    const headerEnd = buffer.indexOf('\r\n\r\n');
    if (headerEnd === -1) break;
    const header = buffer.substring(0, headerEnd);
    const m = header.match(/Content-Length:\s*(\d+)/i);
    if (!m) { buffer = buffer.substring(headerEnd + 4); continue; }
    const len = parseInt(m[1]);
    const bodyStart = headerEnd + 4;
    if (buffer.length < bodyStart + len) break;
    const body = buffer.substring(bodyStart, bodyStart + len);
    buffer = buffer.substring(bodyStart + len);
    try {
      handleRequest(JSON.parse(body));
    } catch (e) {
      process.stderr.write(`[computer-use] Parse error: ${e.message}\n`);
    }
  }
});

process.stdin.on('end', () => process.exit(0));
process.stderr.write(`[computer-use] Linux MCP server started (screen: ${SCREEN.width}x${SCREEN.height})\n`);
