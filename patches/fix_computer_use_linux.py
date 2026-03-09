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
    #
    # The BR() factory must return an object with connect(transport), close(),
    # and a transport property. When connect() is called with a MessagePort
    # transport, we spawn the child process and bridge messages between the
    # transport and the stdio-based MCP server.
    # The proxy object mimics PNe (MCP Protocol base class):
    # - connect(transport): called by k6t with a qMe (MessagePort) transport
    #   Sets transport.onmessage to forward app→child, reads child stdout→transport.send()
    #   Does NOT call transport.start() — the caller (PNe.connect flow) handles that
    # - close(): kills child process and closes transport
    # - transport: getter for the current transport
    inject_js = (
        'if(process.platform==="linux"){'
        'const _cuPath=require("path").join('
        'require("electron").app.getAppPath(),"computer-use-server.js");'
        'if(require("fs").existsSync(_cuPath)){'
        + br_name + '("computer-use","cu-"+Date.now(),()=>{'
        'const _proxy={_transport:null,_proc:null,_buf:"",'
        'get transport(){return this._transport},'
        'async connect(tr){'
        'if(this._transport)await this.close();'
        'this._transport=tr;'
        'const _cp=require("child_process");'
        'this._proc=_cp.spawn(process.execPath,[_cuPath],'
        '{stdio:["pipe","pipe","pipe"],'
        'env:{...process.env,ELECTRON_RUN_AS_NODE:"1"}});'
        'this._proc.stderr.on("data",d=>console.log("[computer-use]",d.toString().trim()));'
        'this._proc.on("exit",(c)=>console.log("[computer-use] exited",c));'
        'this._proc.stdout.on("data",chunk=>{'
        'this._buf+=chunk.toString();'
        'let idx;'
        'while((idx=this._buf.indexOf("\\r\\n\\r\\n"))!==-1){'
        'const hdr=this._buf.substring(0,idx);'
        'const cm=hdr.match(/Content-Length:\\s*(\\d+)/i);'
        'if(!cm){this._buf=this._buf.substring(idx+4);continue}'
        'const clen=parseInt(cm[1]);'
        'const bstart=idx+4;'
        'if(this._buf.length<bstart+clen)break;'
        'const body=this._buf.substring(bstart,bstart+clen);'
        'this._buf=this._buf.substring(bstart+clen);'
        'try{tr.send(JSON.parse(body))}catch(e){}'
        '}'
        '});'
        'const _origOnclose=tr.onclose;'
        'tr.onclose=()=>{_origOnclose&&_origOnclose();'
        'if(this._proc){this._proc.kill();this._proc=null}};'
        'tr.onmessage=msg=>{'
        'if(!this._proc)return;'
        'const s=JSON.stringify(msg);'
        'this._proc.stdin.write("Content-Length: "+Buffer.byteLength(s)+"\\r\\n\\r\\n"+s)};'
        'await tr.start()'
        '},'
        'async close(){'
        'if(this._proc){this._proc.kill();this._proc=null}'
        'if(this._transport){const t=this._transport;this._transport=null;'
        'try{await t.close()}catch(e){}}'
        '}'
        '};return _proxy'
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
