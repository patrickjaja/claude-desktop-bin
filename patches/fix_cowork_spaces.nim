# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Register a full file-based CoworkSpaces service on Linux.
#
# On macOS/Windows, the CoworkSpaces eipc handlers are registered by the native
# Cowork backend (claude-swift) during session manager initialization. On Linux,
# this doesn't happen because the native backend is not loaded.
#
# This patch injects a complete local Spaces service that:
# - Stores spaces as JSON in <userData>/spaces.json
# - Implements full CRUD for spaces, folders, projects, links
# - Handles real file operations (listFolderContents, readFileContents, openFile)
# - Emits space_event push events to renderer via webContents.send()
# - Sets itself on the SpaceManager singleton so resolveSpaceContext works

import std/[os, strformat, strutils]
import std/nre

const EXPECTED_PATCHES = 3

proc extractEipcUuid(content: string): string =
  let m = content.find(re"\$eipc_message\$_([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})")
  if m.isSome:
    return m.get().captures[0]
  return ""

proc extractSpaceManagerSingleton(content: string): string =
  let m = content.find(re"\(\w+=(\w+)\.peek\(\)\)==null\?void 0:\w+\.getSpace\(")
  if m.isSome:
    return m.get().captures[0]
  return ""

proc buildSpacesServiceJs(eipcPrefix, singletonVar: string): string =
  let eventChannel = eipcPrefix & "onSpaceEvent"

  result = "if(process.platform===\"linux\"){" &
    "const _ipc=require(\"electron\").ipcMain;" &
    "const _BW=require(\"electron\").BrowserWindow;" &
    "const _shell=require(\"electron\").shell;" &
    "const _app=require(\"electron\").app;" &
    "const _fs=require(\"fs\");" &
    "const _path=require(\"path\");" &
    "const _crypto=require(\"crypto\");" &
    "const _EE=require(\"events\").EventEmitter;" &
    "const _P=\"" & eipcPrefix & "\";" &
    "const _EVT=\"" & eventChannel & "\";" &
    "class _SpacesService extends _EE{" &
    "constructor(){" &
    "super();" &
    "this._file=_path.join(_app.getPath(\"userData\"),\"spaces.json\");" &
    "this._spaces=[];" &
    "this._load();" &
    "}" &
    "_load(){" &
    "try{" &
    "if(_fs.existsSync(this._file)){" &
    "const d=_fs.readFileSync(this._file,\"utf-8\");" &
    "const p=JSON.parse(d);" &
    "this._spaces=Array.isArray(p.spaces)?p.spaces:Array.isArray(p)?p:[];" &
    "}" &
    "}catch(e){console.error(\"[SpacesService] load error:\",e);this._spaces=[];}" &
    "}" &
    "_save(){" &
    "try{" &
    "const dir=_path.dirname(this._file);" &
    "if(!_fs.existsSync(dir))_fs.mkdirSync(dir,{recursive:true});" &
    "_fs.writeFileSync(this._file,JSON.stringify({spaces:this._spaces},null,2));" &
    "}catch(e){console.error(\"[SpacesService] save error:\",e);}" &
    "}" &
    "_notify(evt){" &
    "this.emit(\"space_event\",evt);" &
    "try{" &
    "const wins=_BW.getAllWindows();" &
    "for(const w of wins){" &
    "if(w.webContents&&!w.webContents.isDestroyed())" &
    "w.webContents.send(_EVT,evt);" &
    "}" &
    "}catch(e){}" &
    "}" &
    "_find(id){return this._spaces.find(s=>s.id===id)||null;}" &
    "getAllSpaces(){return this._spaces;}" &
    "getSpace(id){return this._find(id);}" &
    "createSpace(data){" &
    "const now=new Date().toISOString();" &
    "const id=_crypto.randomUUID();" &
    "const space={" &
    "id," &
    "name:data.name||\"Untitled Space\"," &
    "description:data.description||undefined," &
    "folders:Array.isArray(data.folders)?data.folders:[]," &
    "projects:Array.isArray(data.projects)?data.projects:[]," &
    "links:Array.isArray(data.links)?data.links:[]," &
    "instructions:data.instructions||undefined," &
    "ccdFolderPath:data.ccdFolderPath||_path.join(_app.getPath(\"userData\"),\"spaces\",id)," &
    "createdAt:now," &
    "updatedAt:now" &
    "};" &
    "try{_fs.mkdirSync(space.ccdFolderPath,{recursive:true});}catch(e){}" &
    "this._spaces.push(space);" &
    "this._save();" &
    "this._notify({type:\"created\",space});" &
    "return space;" &
    "}" &
    "updateSpace(id,updates){" &
    "const s=this._find(id);" &
    "if(!s)return null;" &
    "if(updates.name!==undefined)s.name=updates.name;" &
    "if(updates.description!==undefined)s.description=updates.description;" &
    "if(updates.instructions!==undefined)s.instructions=updates.instructions;" &
    "if(updates.folders!==undefined)s.folders=updates.folders;" &
    "if(updates.projects!==undefined)s.projects=updates.projects;" &
    "if(updates.links!==undefined)s.links=updates.links;" &
    "if(updates.ccdFolderPath!==undefined)s.ccdFolderPath=updates.ccdFolderPath;" &
    "s.updatedAt=new Date().toISOString();" &
    "this._save();" &
    "this._notify({type:\"updated\",space:s});" &
    "return s;" &
    "}" &
    "deleteSpace(id){" &
    "const idx=this._spaces.findIndex(s=>s.id===id);" &
    "if(idx===-1)return null;" &
    "const removed=this._spaces.splice(idx,1)[0];" &
    "this._save();" &
    "this._notify({type:\"deleted\",spaceId:id});" &
    "return removed;" &
    "}" &
    "addFolderToSpace(id,folder){" &
    "const s=this._find(id);" &
    "if(!s)return null;" &
    "const p=typeof folder===\"string\"?folder:folder.path;" &
    "if(!s.folders.some(f=>f.path===p)){" &
    "s.folders.push({path:p});" &
    "s.updatedAt=new Date().toISOString();" &
    "this._save();" &
    "this._notify({type:\"updated\",space:s});" &
    "}" &
    "return s;" &
    "}" &
    "removeFolderFromSpace(id,folderPath){" &
    "const s=this._find(id);" &
    "if(!s)return null;" &
    "const p=typeof folderPath===\"string\"?folderPath:folderPath.path;" &
    "s.folders=s.folders.filter(f=>f.path!==p);" &
    "s.updatedAt=new Date().toISOString();" &
    "this._save();" &
    "this._notify({type:\"updated\",space:s});" &
    "return s;" &
    "}" &
    "addProjectToSpace(id,project){" &
    "const s=this._find(id);" &
    "if(!s)return null;" &
    "const u=typeof project===\"string\"?project:project.uuid;" &
    "if(!s.projects.some(p=>p.uuid===u)){" &
    "s.projects.push({uuid:u});" &
    "s.updatedAt=new Date().toISOString();" &
    "this._save();" &
    "this._notify({type:\"updated\",space:s});" &
    "}" &
    "return s;" &
    "}" &
    "removeProjectFromSpace(id,projectUuid){" &
    "const s=this._find(id);" &
    "if(!s)return null;" &
    "const u=typeof projectUuid===\"string\"?projectUuid:projectUuid.uuid;" &
    "s.projects=s.projects.filter(p=>p.uuid!==u);" &
    "s.updatedAt=new Date().toISOString();" &
    "this._save();" &
    "this._notify({type:\"updated\",space:s});" &
    "return s;" &
    "}" &
    "addLinkToSpace(id,link){" &
    "const s=this._find(id);" &
    "if(!s)return null;" &
    "if(!s.links)s.links=[];" &
    "const url=typeof link===\"string\"?link:link.url;" &
    "if(!s.links.some(l=>l.url===url)){" &
    "s.links.push(typeof link===\"string\"?{url:link}:link);" &
    "s.updatedAt=new Date().toISOString();" &
    "this._save();" &
    "this._notify({type:\"updated\",space:s});" &
    "}" &
    "return s;" &
    "}" &
    "removeLinkFromSpace(id,linkUrl){" &
    "const s=this._find(id);" &
    "if(!s)return null;" &
    "const url=typeof linkUrl===\"string\"?linkUrl:linkUrl.url;" &
    "s.links=(s.links||[]).filter(l=>l.url!==url);" &
    "s.updatedAt=new Date().toISOString();" &
    "this._save();" &
    "this._notify({type:\"updated\",space:s});" &
    "return s;" &
    "}" &
    "getAutoMemoryDir(spaceId){" &
    "const s=this._find(spaceId);" &
    "if(!s)return null;" &
    "const dir=_path.join(_app.getPath(\"userData\"),\"spaces\",spaceId,\"memory\");" &
    "try{_fs.mkdirSync(dir,{recursive:true});}catch(e){}" &
    "return dir;" &
    "}" &
    "listFolderContents(spaceId,folderPath){" &
    "const s=this._find(spaceId);" &
    "if(!s)return[];" &
    "const resolved=_path.resolve(folderPath);" &
    "const allowed=s.folders.some(f=>resolved.startsWith(_path.resolve(f.path)))" &
    "||resolved.startsWith(_path.resolve(s.ccdFolderPath||\"\"));" &
    "if(!allowed)return[];" &
    "try{" &
    "const entries=_fs.readdirSync(resolved,{withFileTypes:true});" &
    "return entries.map(e=>({" &
    "name:e.name," &
    "isDirectory:e.isDirectory()," &
    "path:_path.join(resolved,e.name)" &
    "}));" &
    "}catch(e){return[];}" &
    "}" &
    "readFileContents(spaceId,filePath){" &
    "const s=this._find(spaceId);" &
    "if(!s)return null;" &
    "const resolved=_path.resolve(filePath);" &
    "const allowed=s.folders.some(f=>resolved.startsWith(_path.resolve(f.path)))" &
    "||resolved.startsWith(_path.resolve(s.ccdFolderPath||\"\"));" &
    "if(!allowed)return null;" &
    "try{return _fs.readFileSync(resolved,\"utf-8\");}catch(e){return null;}" &
    "}" &
    "openFile(spaceId,filePath){" &
    "try{_shell.openPath(_path.resolve(filePath));}catch(e){}" &
    "return null;" &
    "}" &
    "createSpaceFolder(parentPath,folderName){" &
    "if(!folderName||!folderName.trim())return null;" &
    "const name=folderName.trim();" &
    "let dir=_path.join(parentPath,name);" &
    "let n=0;" &
    "while(_fs.existsSync(dir)){n++;dir=_path.join(parentPath,name+\" (\"+n+\")\");}" &
    "try{_fs.mkdirSync(dir,{recursive:true});return dir;}catch(e){return null;}" &
    "}" &
    "copyFilesToSpaceFolder(spaceId,files){" &
    "const s=this._find(spaceId);" &
    "if(!s||!s.ccdFolderPath)return null;" &
    "const results=[];" &
    "const flist=Array.isArray(files)?files:[];" &
    "for(const f of flist){" &
    "try{" &
    "const src=typeof f===\"string\"?f:f.path||f.sourcePath;" &
    "const name=_path.basename(src);" &
    "const dest=_path.join(s.ccdFolderPath,name);" &
    "_fs.copyFileSync(src,dest);" &
    "results.push({name,path:dest,success:true});" &
    "}catch(e){results.push({name:typeof f===\"string\"?_path.basename(f):\"unknown\",success:false,error:e.message});}" &
    "}" &
    "return results;" &
    "}" &
    "}" &  # end class _SpacesService
    "const _svc=new _SpacesService();" &
    "_ipc.handle(_P+\"getAllSpaces\",()=>_svc.getAllSpaces());" &
    "_ipc.handle(_P+\"getSpace\",(ev,id)=>_svc.getSpace(id));" &
    "_ipc.handle(_P+\"createSpace\",(ev,data)=>_svc.createSpace(data||{}));" &
    "_ipc.handle(_P+\"updateSpace\",(ev,id,upd)=>_svc.updateSpace(id,upd||{}));" &
    "_ipc.handle(_P+\"deleteSpace\",(ev,id)=>_svc.deleteSpace(id));" &
    "_ipc.handle(_P+\"addFolderToSpace\",(ev,id,f)=>_svc.addFolderToSpace(id,f));" &
    "_ipc.handle(_P+\"removeFolderFromSpace\",(ev,id,f)=>_svc.removeFolderFromSpace(id,f));" &
    "_ipc.handle(_P+\"addProjectToSpace\",(ev,id,p)=>_svc.addProjectToSpace(id,p));" &
    "_ipc.handle(_P+\"removeProjectFromSpace\",(ev,id,p)=>_svc.removeProjectFromSpace(id,p));" &
    "_ipc.handle(_P+\"addLinkToSpace\",(ev,id,l)=>_svc.addLinkToSpace(id,l));" &
    "_ipc.handle(_P+\"removeLinkFromSpace\",(ev,id,l)=>_svc.removeLinkFromSpace(id,l));" &
    "_ipc.handle(_P+\"getAutoMemoryDir\",(ev,id)=>_svc.getAutoMemoryDir(id));" &
    "_ipc.handle(_P+\"listFolderContents\",(ev,id,p)=>_svc.listFolderContents(id,p));" &
    "_ipc.handle(_P+\"readFileContents\",(ev,id,p)=>_svc.readFileContents(id,p));" &
    "_ipc.handle(_P+\"openFile\",(ev,id,p)=>_svc.openFile(id,p));" &
    "_ipc.handle(_P+\"createSpaceFolder\",(ev,parentPath,name)=>_svc.createSpaceFolder(parentPath,name));" &
    "_ipc.handle(_P+\"copyFilesToSpaceFolder\",(ev,id,f)=>_svc.copyFilesToSpaceFolder(id,f));" &
    "try{" & singletonVar & ".set(_svc);" &
    "console.log(\"[SpacesService] Registered on " & singletonVar & " singleton\");" &
    "}catch(_e){console.warn(\"[SpacesService] Could not set singleton:\",_e);}" &
    "console.log(\"[SpacesService] Linux CoworkSpaces service initialized with\",_svc._spaces.length,\"spaces\");" &
    "}"  # end if(process.platform==="linux")

proc apply*(input: string): string =
  result = input
  var patchesApplied = 0

  # --- Step 0: Check if full service is already injected (idempotency) ---
  if "class _SpacesService extends _EE{" in result:
    echo "  [OK] Full CoworkSpaces service already injected (idempotent)"
    echo &"  [PASS] {EXPECTED_PATCHES}/{EXPECTED_PATCHES} patches applied (already patched)"
    return

  # --- Step 1 (Patch A): Extract eipc UUID ---
  var uuid = extractEipcUuid(result)
  if uuid == "":
    echo "  [FAIL] Patch A: Could not extract eipc UUID from source files"
    quit(1)

  let eipcPrefix = "$eipc_message$_" & uuid & "_$_claude.web_$_CoworkSpaces_$_"
  echo &"  [OK] Patch A: Extracted eipc UUID: {uuid}"
  inc patchesApplied

  # --- Step 2 (Patch B): Find SpaceManager singleton variable name ---
  var singletonVar = extractSpaceManagerSingleton(result)
  if singletonVar == "":
    echo "  [INFO] Patch B: primary singleton regex didn't match, trying fallback"
    let fallbackMatch = result.find(re"peek\(\)\{return this\.current\}\}const (\w+)=new \w+,")
    if fallbackMatch.isSome:
      singletonVar = fallbackMatch.get().captures[0]
      echo &"  [OK] Patch B: Found singleton via fallback pattern: {singletonVar}"
    else:
      echo "  [FAIL] Patch B: Could not find SpaceManager singleton variable."
      quit(1)
  else:
    echo &"  [OK] Patch B: SpaceManager singleton (primary regex): {singletonVar}"
  inc patchesApplied

  # --- Step 3: Remove any existing CoworkSpaces stubs (cleanup, not counted) ---
  let oldStubPattern = re"""if\(process\.platform==="linux"\)\{const _ipc=require\("electron"\)\.ipcMain;const _P="\$eipc_message\$_[a-f0-9-]+_\$_claude\.web_\$_CoworkSpaces_\$_";[^}]*\}"""
  var removed = 0
  result = result.replace(oldStubPattern, proc(m: RegexMatch): string =
    inc removed
    ""
  )
  if removed > 0:
    echo &"  [OK] Removed {removed} old CoworkSpaces stub block(s)"

  # --- Step 4 (Patch C): Build and inject the full service ---
  let serviceJs = buildSpacesServiceJs(eipcPrefix, singletonVar)

  let readyPattern = re"""app\.on\("ready",async\(\)=>\{"""
  var countC = 0
  result = result.replace(readyPattern, proc(m: RegexMatch): string =
    inc countC
    if countC > 1:
      return m.match  # only replace first
    m.match & serviceJs
  )
  if countC >= 1:
    echo &"  [OK] Patch C: CoworkSpaces service injected ({countC} match)"
    inc patchesApplied
  else:
    echo "  [FAIL] Patch C: app.on(\"ready\") pattern: 0 matches"
    quit(1)

  # --- Strict enforcement ---
  if patchesApplied < EXPECTED_PATCHES:
    echo &"  [FAIL] Only {patchesApplied}/{EXPECTED_PATCHES} patches applied"
    quit(1)

  if result == input:
    echo "  [FAIL] Patches reported success but file content unchanged"
    quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: fix_cowork_spaces <path_to_index.js>"
    quit(1)

  let filePath = paramStr(1)
  echo "=== Patch: fix_cowork_spaces ==="
  echo "  Target: " & filePath

  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)

  # Also try mainView.js for UUID extraction if needed
  let input = readFile(filePath)
  let output = apply(input)

  if output != input:
    writeFile(filePath, output)
    echo &"  [PASS] {EXPECTED_PATCHES}/{EXPECTED_PATCHES} patches applied -- CoworkSpaces file-based service registered for Linux"
