#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Register Linux computer-use MCP server as an internal MCP server.

On macOS, computer-use tools are provided by @ant/claude-swift (native Swift).
On Linux, we register a Node.js MCP server (computer-use-server.js) that uses
xdotool for input and scrot for screenshots.

The server is registered via the internal MCP server registry so it appears
as "computer-use", matching the mcp__computer-use tool prefix in allowedTools.

Usage: python3 fix_computer_use_linux.py <path_to_index.js>
"""

import sys
import os
import re


def patch_computer_use_linux(filepath):
    """Register Linux computer-use MCP server."""

    print("=== Patch: fix_computer_use_linux ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, 'rb') as f:
        content = f.read()

    original_content = content

    # Find the BR (registerInternalMcpServer) function name
    br_pattern = rb'function (\w+)\((\w+),(\w+),(\w+)\)\{return (\w+)\[\2\]=\4,(\w+)\[\2\]=\3,'
    br_match = re.search(br_pattern, content)
    if not br_match:
        print("  [FAIL] register function not found")
        return False

    br_name = br_match.group(1).decode('utf-8')
    print(f"  [OK] Found register function: {br_name}")

    # Build injection JS — register computer-use MCP server on Linux
    # This spawns computer-use-server.js as a child process and wraps it
    # in the {read, write, close} interface that createProxyServers expects.
    inject_js = (
        'if(process.platform==="linux"){'
        'const _cuPath=require("path").join('
        'require("electron").app.getAppPath(),"computer-use-server.js");'
        'if(require("fs").existsSync(_cuPath)){'
        + br_name + '("computer-use","cu-"+Date.now(),()=>{'
        'const _cp=require("child_process");'
        'const _proc=_cp.spawn(process.execPath,["--no-sandbox",_cuPath],'
        '{stdio:["pipe","pipe","pipe"],'
        'env:{...process.env,ELECTRON_RUN_AS_NODE:"1"}});'
        '_proc.stderr.on("data",d=>console.log("[computer-use]",d.toString().trim()));'
        '_proc.on("exit",(c)=>console.log("[computer-use] exited",c));'
        'let _buf="";'
        'return{read:cb=>{_proc.stdout.on("data",chunk=>{'
        '_buf+=chunk.toString();'
        'let idx;'
        'while((idx=_buf.indexOf("\\r\\n\\r\\n"))!==-1){'
        'const hdr=_buf.substring(0,idx);'
        'const cm=hdr.match(/Content-Length:\\s*(\\d+)/i);'
        'if(!cm){_buf=_buf.substring(idx+4);continue}'
        'const clen=parseInt(cm[1]);'
        'const bstart=idx+4;'
        'if(_buf.length<bstart+clen)break;'
        'const body=_buf.substring(bstart,bstart+clen);'
        '_buf=_buf.substring(bstart+clen);'
        'try{cb(JSON.parse(body))}catch(e){}'
        '}'
        '})},write:msg=>{'
        'const s=JSON.stringify(msg);'
        '_proc.stdin.write("Content-Length: "+Buffer.byteLength(s)+"\\r\\n\\r\\n"+s)'
        '},close:()=>_proc.kill()}'
        '})'
        '}}'
    )

    # Inject at app.on("ready")
    ready_pattern = rb'app\.on\("ready",async\(\)=>\{'
    inject_bytes = inject_js.encode('utf-8')

    def replacement(m):
        return m.group(0) + inject_bytes

    content, count = re.subn(ready_pattern, replacement, content, count=1)
    if count >= 1:
        print(f"  [OK] computer-use MCP server: registered ({count} match)")
    else:
        print('  [FAIL] app.on("ready") pattern: 0 matches')
        return False

    if content != original_content:
        with open(filepath, 'wb') as f:
            f.write(content)
        print("  [PASS] Linux computer-use MCP server registered")
        return True
    else:
        print("  [WARN] No changes made")
        return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_computer_use_linux(sys.argv[1])
    sys.exit(0 if success else 1)
