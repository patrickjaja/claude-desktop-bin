#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Register a full file-based CoworkSpaces service on Linux.

On macOS/Windows, the CoworkSpaces eipc handlers are registered by the native
Cowork backend (claude-swift) during session manager initialization. On Linux,
this doesn't happen because the native backend is not loaded.

This patch injects a complete local Spaces service that:
- Stores spaces as JSON in <userData>/spaces.json
- Implements full CRUD for spaces, folders, projects, links
- Handles real file operations (listFolderContents, readFileContents, openFile)
- Emits space_event push events to renderer via webContents.send()
- Sets itself on the SpaceManager singleton so resolveSpaceContext works

Space schema:
  {id, name, description?, folders: [{path}], projects: [{uuid}],
   links: [{url, title?, provider?}], instructions?, ccdFolderPath?,
   createdAt, updatedAt}

Usage: python3 fix_cowork_spaces.py <path_to_index.js>
"""

import sys
import os
import re


# Number of required sub-patches that must succeed on a pristine build:
#   A: eipc UUID extraction
#   B: SpaceManager singleton variable name extraction (primary or fallback regex)
#   C: Service injection after app.on("ready", ...)
# The "remove old stubs" step is a cleanup that may legitimately be a no-op on
# pristine upstream, so it is NOT counted here.
EXPECTED_PATCHES = 3


def extract_eipc_uuid(content):
    """Extract the eipc UUID from the file content dynamically."""
    m = re.search(
        rb"\$eipc_message\$_([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})",
        content,
    )
    if m:
        return m.group(1).decode("utf-8")
    return None


def extract_space_manager_singleton(content):
    """Extract the minified SpaceManager singleton variable name.

    The singleton is used in resolveSpaceContext like:
      (r=K6e.peek())==null?void 0:r.getSpace(t)
    We capture the variable name from that pattern.
    """
    # Pattern: (r=VARNAME.peek())==null?void 0:r.getSpace(
    m = re.search(rb"\(\w+=(\w+)\.peek\(\)\)==null\?void 0:\w+\.getSpace\(", content)
    if m:
        return m.group(1).decode("utf-8")
    return None


def build_spaces_service_js(eipc_prefix, singleton_var):
    """Build the full SpacesService implementation JS code."""

    # The onSpaceEvent push channel (renderer listens via ipcRenderer.on)
    event_channel = f"{eipc_prefix}onSpaceEvent"

    return (
        'if(process.platform==="linux"){'
        # Dependencies
        'const _ipc=require("electron").ipcMain;'
        'const _BW=require("electron").BrowserWindow;'
        'const _shell=require("electron").shell;'
        'const _app=require("electron").app;'
        'const _fs=require("fs");'
        'const _path=require("path");'
        'const _crypto=require("crypto");'
        'const _EE=require("events").EventEmitter;'
        f'const _P="{eipc_prefix}";'
        f'const _EVT="{event_channel}";'
        # SpacesService class
        "class _SpacesService extends _EE{"
        "constructor(){"
        "super();"
        'this._file=_path.join(_app.getPath("userData"),"spaces.json");'
        "this._spaces=[];"
        "this._load();"
        "}"
        # Load from disk
        "_load(){"
        "try{"
        "if(_fs.existsSync(this._file)){"
        'const d=_fs.readFileSync(this._file,"utf-8");'
        "const p=JSON.parse(d);"
        "this._spaces=Array.isArray(p.spaces)?p.spaces:Array.isArray(p)?p:[];"
        "}"
        '}catch(e){console.error("[SpacesService] load error:",e);this._spaces=[];}'
        "}"
        # Save to disk
        "_save(){"
        "try{"
        "const dir=_path.dirname(this._file);"
        "if(!_fs.existsSync(dir))_fs.mkdirSync(dir,{recursive:true});"
        "_fs.writeFileSync(this._file,JSON.stringify({spaces:this._spaces},null,2));"
        '}catch(e){console.error("[SpacesService] save error:",e);}'
        "}"
        # Push event to all renderer windows AND emit for K6e
        "_notify(evt){"
        'this.emit("space_event",evt);'
        "try{"
        "const wins=_BW.getAllWindows();"
        "for(const w of wins){"
        "if(w.webContents&&!w.webContents.isDestroyed())"
        "w.webContents.send(_EVT,evt);"
        "}"
        "}catch(e){}"
        "}"
        # Find space by id
        "_find(id){return this._spaces.find(s=>s.id===id)||null;}"
        # getAllSpaces
        "getAllSpaces(){return this._spaces;}"
        # getSpace
        "getSpace(id){return this._find(id);}"
        # createSpace
        "createSpace(data){"
        "const now=new Date().toISOString();"
        "const id=_crypto.randomUUID();"
        "const space={"
        "id,"
        'name:data.name||"Untitled Space",'
        "description:data.description||undefined,"
        "folders:Array.isArray(data.folders)?data.folders:[],"
        "projects:Array.isArray(data.projects)?data.projects:[],"
        "links:Array.isArray(data.links)?data.links:[],"
        "instructions:data.instructions||undefined,"
        'ccdFolderPath:data.ccdFolderPath||_path.join(_app.getPath("userData"),"spaces",id),'
        "createdAt:now,"
        "updatedAt:now"
        "};"
        "try{_fs.mkdirSync(space.ccdFolderPath,{recursive:true});}catch(e){}"
        "this._spaces.push(space);"
        "this._save();"
        'this._notify({type:"created",space});'
        "return space;"
        "}"
        # updateSpace
        "updateSpace(id,updates){"
        "const s=this._find(id);"
        "if(!s)return null;"
        "if(updates.name!==undefined)s.name=updates.name;"
        "if(updates.description!==undefined)s.description=updates.description;"
        "if(updates.instructions!==undefined)s.instructions=updates.instructions;"
        "if(updates.folders!==undefined)s.folders=updates.folders;"
        "if(updates.projects!==undefined)s.projects=updates.projects;"
        "if(updates.links!==undefined)s.links=updates.links;"
        "if(updates.ccdFolderPath!==undefined)s.ccdFolderPath=updates.ccdFolderPath;"
        "s.updatedAt=new Date().toISOString();"
        "this._save();"
        'this._notify({type:"updated",space:s});'
        "return s;"
        "}"
        # deleteSpace
        "deleteSpace(id){"
        "const idx=this._spaces.findIndex(s=>s.id===id);"
        "if(idx===-1)return null;"
        "const removed=this._spaces.splice(idx,1)[0];"
        "this._save();"
        'this._notify({type:"deleted",spaceId:id});'
        "return removed;"
        "}"
        # addFolderToSpace
        "addFolderToSpace(id,folder){"
        "const s=this._find(id);"
        "if(!s)return null;"
        'const p=typeof folder==="string"?folder:folder.path;'
        "if(!s.folders.some(f=>f.path===p)){"
        "s.folders.push({path:p});"
        "s.updatedAt=new Date().toISOString();"
        "this._save();"
        'this._notify({type:"updated",space:s});'
        "}"
        "return s;"
        "}"
        # removeFolderFromSpace
        "removeFolderFromSpace(id,folderPath){"
        "const s=this._find(id);"
        "if(!s)return null;"
        'const p=typeof folderPath==="string"?folderPath:folderPath.path;'
        "s.folders=s.folders.filter(f=>f.path!==p);"
        "s.updatedAt=new Date().toISOString();"
        "this._save();"
        'this._notify({type:"updated",space:s});'
        "return s;"
        "}"
        # addProjectToSpace
        "addProjectToSpace(id,project){"
        "const s=this._find(id);"
        "if(!s)return null;"
        'const u=typeof project==="string"?project:project.uuid;'
        "if(!s.projects.some(p=>p.uuid===u)){"
        "s.projects.push({uuid:u});"
        "s.updatedAt=new Date().toISOString();"
        "this._save();"
        'this._notify({type:"updated",space:s});'
        "}"
        "return s;"
        "}"
        # removeProjectFromSpace
        "removeProjectFromSpace(id,projectUuid){"
        "const s=this._find(id);"
        "if(!s)return null;"
        'const u=typeof projectUuid==="string"?projectUuid:projectUuid.uuid;'
        "s.projects=s.projects.filter(p=>p.uuid!==u);"
        "s.updatedAt=new Date().toISOString();"
        "this._save();"
        'this._notify({type:"updated",space:s});'
        "return s;"
        "}"
        # addLinkToSpace
        "addLinkToSpace(id,link){"
        "const s=this._find(id);"
        "if(!s)return null;"
        "if(!s.links)s.links=[];"
        'const url=typeof link==="string"?link:link.url;'
        "if(!s.links.some(l=>l.url===url)){"
        's.links.push(typeof link==="string"?{url:link}:link);'
        "s.updatedAt=new Date().toISOString();"
        "this._save();"
        'this._notify({type:"updated",space:s});'
        "}"
        "return s;"
        "}"
        # removeLinkFromSpace
        "removeLinkFromSpace(id,linkUrl){"
        "const s=this._find(id);"
        "if(!s)return null;"
        'const url=typeof linkUrl==="string"?linkUrl:linkUrl.url;'
        "s.links=(s.links||[]).filter(l=>l.url!==url);"
        "s.updatedAt=new Date().toISOString();"
        "this._save();"
        'this._notify({type:"updated",space:s});'
        "return s;"
        "}"
        # getAutoMemoryDir
        "getAutoMemoryDir(spaceId){"
        "const s=this._find(spaceId);"
        "if(!s)return null;"
        'const dir=_path.join(_app.getPath("userData"),"spaces",spaceId,"memory");'
        "try{_fs.mkdirSync(dir,{recursive:true});}catch(e){}"
        "return dir;"
        "}"
        # listFolderContents
        "listFolderContents(spaceId,folderPath){"
        "const s=this._find(spaceId);"
        "if(!s)return[];"
        # Security: ensure folderPath is within one of the space's folders
        "const resolved=_path.resolve(folderPath);"
        "const allowed=s.folders.some(f=>resolved.startsWith(_path.resolve(f.path)))"
        '||resolved.startsWith(_path.resolve(s.ccdFolderPath||""));'
        "if(!allowed)return[];"
        "try{"
        "const entries=_fs.readdirSync(resolved,{withFileTypes:true});"
        "return entries.map(e=>({"
        "name:e.name,"
        "isDirectory:e.isDirectory(),"
        "path:_path.join(resolved,e.name)"
        "}));"
        "}catch(e){return[];}"
        "}"
        # readFileContents
        "readFileContents(spaceId,filePath){"
        "const s=this._find(spaceId);"
        "if(!s)return null;"
        "const resolved=_path.resolve(filePath);"
        "const allowed=s.folders.some(f=>resolved.startsWith(_path.resolve(f.path)))"
        '||resolved.startsWith(_path.resolve(s.ccdFolderPath||""));'
        "if(!allowed)return null;"
        'try{return _fs.readFileSync(resolved,"utf-8");}catch(e){return null;}'
        "}"
        # openFile
        "openFile(spaceId,filePath){"
        "try{_shell.openPath(_path.resolve(filePath));}catch(e){}"
        "return null;"
        "}"
        # createSpaceFolder — takes (parentPath, folderName), NOT spaceId
        "createSpaceFolder(parentPath,folderName){"
        "if(!folderName||!folderName.trim())return null;"
        "const name=folderName.trim();"
        "let dir=_path.join(parentPath,name);"
        "let n=0;"
        'while(_fs.existsSync(dir)){n++;dir=_path.join(parentPath,name+" ("+n+")");}'
        "try{_fs.mkdirSync(dir,{recursive:true});return dir;}catch(e){return null;}"
        "}"
        # copyFilesToSpaceFolder
        "copyFilesToSpaceFolder(spaceId,files){"
        "const s=this._find(spaceId);"
        "if(!s||!s.ccdFolderPath)return null;"
        "const results=[];"
        "const flist=Array.isArray(files)?files:[];"
        "for(const f of flist){"
        "try{"
        'const src=typeof f==="string"?f:f.path||f.sourcePath;'
        "const name=_path.basename(src);"
        "const dest=_path.join(s.ccdFolderPath,name);"
        "_fs.copyFileSync(src,dest);"
        "results.push({name,path:dest,success:true});"
        '}catch(e){results.push({name:typeof f==="string"?_path.basename(f):"unknown",success:false,error:e.message});}'
        "}"
        "return results;"
        "}"
        # End of class
        "}"  # end class _SpacesService
        # Create the service instance
        "const _svc=new _SpacesService();"
        # Register all IPC handlers
        '_ipc.handle(_P+"getAllSpaces",()=>_svc.getAllSpaces());'
        '_ipc.handle(_P+"getSpace",(ev,id)=>_svc.getSpace(id));'
        '_ipc.handle(_P+"createSpace",(ev,data)=>_svc.createSpace(data||{}));'
        '_ipc.handle(_P+"updateSpace",(ev,id,upd)=>_svc.updateSpace(id,upd||{}));'
        '_ipc.handle(_P+"deleteSpace",(ev,id)=>_svc.deleteSpace(id));'
        '_ipc.handle(_P+"addFolderToSpace",(ev,id,f)=>_svc.addFolderToSpace(id,f));'
        '_ipc.handle(_P+"removeFolderFromSpace",(ev,id,f)=>_svc.removeFolderFromSpace(id,f));'
        '_ipc.handle(_P+"addProjectToSpace",(ev,id,p)=>_svc.addProjectToSpace(id,p));'
        '_ipc.handle(_P+"removeProjectFromSpace",(ev,id,p)=>_svc.removeProjectFromSpace(id,p));'
        '_ipc.handle(_P+"addLinkToSpace",(ev,id,l)=>_svc.addLinkToSpace(id,l));'
        '_ipc.handle(_P+"removeLinkFromSpace",(ev,id,l)=>_svc.removeLinkFromSpace(id,l));'
        '_ipc.handle(_P+"getAutoMemoryDir",(ev,id)=>_svc.getAutoMemoryDir(id));'
        '_ipc.handle(_P+"listFolderContents",(ev,id,p)=>_svc.listFolderContents(id,p));'
        '_ipc.handle(_P+"readFileContents",(ev,id,p)=>_svc.readFileContents(id,p));'
        '_ipc.handle(_P+"openFile",(ev,id,p)=>_svc.openFile(id,p));'
        '_ipc.handle(_P+"createSpaceFolder",(ev,parentPath,name)=>_svc.createSpaceFolder(parentPath,name));'
        '_ipc.handle(_P+"copyFilesToSpaceFolder",(ev,id,f)=>_svc.copyFilesToSpaceFolder(id,f));'
        # Set the service on the SpaceManager singleton so resolveSpaceContext works
        f"try{{{singleton_var}.set(_svc);"
        f'console.log("[SpacesService] Registered on {singleton_var} singleton");'
        '}catch(_e){console.warn("[SpacesService] Could not set singleton:",_e);}'
        'console.log("[SpacesService] Linux CoworkSpaces service initialized with",_svc._spaces.length,"spaces");'
        "}"  # end if(process.platform==="linux")
    )


def patch_cowork_spaces(filepath):
    """Register CoworkSpaces file-based service on Linux."""

    print("=== Patch: fix_cowork_spaces ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content
    patches_applied = 0

    # --- Step 0: Check if full service is already injected (idempotency) ---
    # "Already patched" is success — all sub-patches count as applied.
    if b"class _SpacesService extends _EE{" in content:
        print("  [OK] Full CoworkSpaces service already injected (idempotent)")
        print(f"  [PASS] {EXPECTED_PATCHES}/{EXPECTED_PATCHES} patches applied (already patched)")
        return True

    # --- Step 1 (Patch A): Extract eipc UUID ---
    uuid = extract_eipc_uuid(content)
    if not uuid:
        mainview = os.path.join(os.path.dirname(filepath), "mainView.js")
        if os.path.exists(mainview):
            with open(mainview, "rb") as f:
                uuid = extract_eipc_uuid(f.read())
    if not uuid:
        print("  [FAIL] Patch A: Could not extract eipc UUID from source files")
        return False

    eipc_prefix = f"$eipc_message$_{uuid}_$_claude.web_$_CoworkSpaces_$_"
    print(f"  [OK] Patch A: Extracted eipc UUID: {uuid}")
    patches_applied += 1

    # --- Step 2 (Patch B): Find SpaceManager singleton variable name ---
    # Primary regex, then fallback regex. If BOTH fail, this is a FAIL —
    # do NOT guess with a dummy name, because resolveSpaceContext won't work
    # and the user will silently lose a feature. This is exactly the silent-
    # bug class the Patch Strictness Rules exist to catch.
    singleton_var = extract_space_manager_singleton(content)
    if not singleton_var:
        print("  [INFO] Patch B: primary singleton regex didn't match, trying fallback")
        # Fallback: try to find it from the $Dt class pattern
        # Pattern: peek(){return this.current}}const VARNAME=new
        m = re.search(rb"peek\(\)\{return this\.current\}\}const (\w+)=new \w+,", content)
        if m:
            singleton_var = m.group(1).decode("utf-8")
            print(f"  [OK] Patch B: Found singleton via fallback pattern: {singleton_var}")
        else:
            print(
                "  [FAIL] Patch B: Could not find SpaceManager singleton variable. "
                "Upstream code likely refactored — update "
                "extract_space_manager_singleton() and the fallback regex. "
                "Refusing to inject with a guessed name because resolveSpaceContext "
                "would silently break."
            )
            return False
    else:
        print(f"  [OK] Patch B: SpaceManager singleton (primary regex): {singleton_var}")
    patches_applied += 1

    # --- Step 3: Remove any existing CoworkSpaces stubs (cleanup, not counted) ---
    # Match the old stub pattern: if(process.platform==="linux"){const _ipc=...CoworkSpaces...}
    # This is a cleanup step that may legitimately be a no-op on pristine upstream,
    # so it is NOT counted toward EXPECTED_PATCHES.
    old_stub_pattern = (
        rb'if\(process\.platform==="linux"\)\{'
        rb'const _ipc=require\("electron"\)\.ipcMain;'
        rb'const _P="\$eipc_message\$_[a-f0-9-]+_\$_claude\.web_\$_CoworkSpaces_\$_";'
        rb"[^}]*\}"
    )
    content, removed = re.subn(old_stub_pattern, b"", content)
    if removed:
        print(f"  [OK] Removed {removed} old CoworkSpaces stub block(s)")

    # --- Step 4 (Patch C): Build and inject the full service ---
    service_js = build_spaces_service_js(eipc_prefix, singleton_var)

    # Inject after app.on("ready", async () => {
    pattern = rb'(app\.on\("ready",async\(\)=>\{)'
    replacement = rb"\1" + service_js.encode("utf-8")

    content, count = re.subn(pattern, replacement, content, count=1)
    if count >= 1:
        print(f"  [OK] Patch C: CoworkSpaces service injected ({count} match)")
        patches_applied += 1
    else:
        print('  [FAIL] Patch C: app.on("ready") pattern: 0 matches')
        return False

    # --- Strict enforcement: all required sub-patches must have succeeded ---
    if patches_applied < EXPECTED_PATCHES:
        print(f"  [FAIL] Only {patches_applied}/{EXPECTED_PATCHES} patches applied")
        return False

    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        print(f"  [PASS] {patches_applied}/{EXPECTED_PATCHES} patches applied — CoworkSpaces file-based service registered for Linux")
        return True
    else:
        # All sub-patches reported success yet content is unchanged — this is
        # an inconsistent state. Fail loudly rather than silently succeeding.
        print("  [FAIL] Patches reported success but file content unchanged")
        return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_cowork_spaces(sys.argv[1])
    sys.exit(0 if success else 1)
