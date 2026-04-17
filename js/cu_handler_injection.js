if(process.platform==="linux"){
var __lxTeachTools=["request_teach_access","teach_step","teach_batch"];
if(__lxTeachTools.indexOf(t)>=0){const __n=__DISPATCHER__(r);const{save_to_disk:__sd,...__s}=e;return await __n(t,__s)}
if(t==="request_access"){var __apps=e.apps||[];var __granted=__apps.map(function(a){return{bundleId:a,displayName:a,grantedAt:Date.now(),tier:"full"}});return{content:[{type:"text",text:JSON.stringify({granted:__granted,denied:[],screenshotFiltering:"none"})}]}}
var ex=globalThis.__linuxExecutor;
if(!ex)return{content:[{type:"text",text:"Linux executor not initialized"}],isError:!0};
globalThis.__cuActiveOrigin=globalThis.__cuActiveOrigin||{x:0,y:0};
function __txC(c){var o=globalThis.__cuActiveOrigin;return[(c[0]||0)+(o?o.x:0),(c[1]||0)+(o?o.y:0)]}
function __untxC(x,y){var o=globalThis.__cuActiveOrigin;return[(x||0)-(o?o.x:0),(y||0)-(o?o.y:0)]}
var __actionTools=new Set(["left_click","right_click","double_click","triple_click","middle_click","left_click_drag","mouse_move","scroll","key","type","hold_key","left_mouse_down","left_mouse_up","computer_batch"]);
async function __hideWindows(fn){var __bws=require("electron").BrowserWindow.getAllWindows().filter(function(w){return!w.isDestroyed()});for(var __i=0;__i<__bws.length;__i++)__bws[__i].setIgnoreMouseEvents(true);try{await new Promise(function(r){setTimeout(r,50)});return await fn()}finally{for(var __i=0;__i<__bws.length;__i++){if(!__bws[__i].isDestroyed())__bws[__i].setIgnoreMouseEvents(false)}}}
if(__actionTools.has(t)){return await __hideWindows(async function(){switch(t){
case"left_click":{var __lc=__txC(e.coordinate||[e.x,e.y]);await ex.click(__lc[0],__lc[1],"left",1);return{content:[{type:"text",text:"Clicked at ("+__lc[0]+","+__lc[1]+")"}]}}
case"right_click":{var __rc=__txC(e.coordinate||[e.x,e.y]);await ex.click(__rc[0],__rc[1],"right",1);return{content:[{type:"text",text:"Right clicked"}]}}
case"double_click":{var __dc=__txC(e.coordinate||[e.x,e.y]);await ex.click(__dc[0],__dc[1],"left",2);return{content:[{type:"text",text:"Double clicked"}]}}
case"triple_click":{var __tc=__txC(e.coordinate||[e.x,e.y]);await ex.click(__tc[0],__tc[1],"left",3);return{content:[{type:"text",text:"Triple clicked"}]}}
case"middle_click":{var __mc=__txC(e.coordinate||[e.x,e.y]);await ex.click(__mc[0],__mc[1],"middle",1);return{content:[{type:"text",text:"Middle clicked"}]}}
case"type":{await ex.type(e.text||"",{viaClipboard:!1});return{content:[{type:"text",text:"Typed text"}]}}
case"key":{await ex.key(e.key||e.text||"",e.count||1);return{content:[{type:"text",text:"Pressed key: "+(e.key||e.text)}]}}
case"scroll":{var __sc=__txC(e.coordinate||[e.x||0,e.y||0]),__dir=e.scroll_direction||e.direction||"down",__amt=e.scroll_amount||e.amount||3,__sv=__dir==="down"?__amt:__dir==="up"?-__amt:0,__sh=__dir==="right"?__amt:__dir==="left"?-__amt:0;await ex.scroll(__sc[0],__sc[1],__sh,__sv);return{content:[{type:"text",text:"Scrolled "+__dir}]}}
case"left_click_drag":{var __dsc=e.start_coordinate?__txC(e.start_coordinate):null,__den=__txC(e.coordinate);await ex.drag(__dsc?{x:__dsc[0],y:__dsc[1]}:void 0,{x:__den[0],y:__den[1]});return{content:[{type:"text",text:"Dragged"}]}}
case"mouse_move":{var __mv=__txC(e.coordinate||[e.x,e.y]);await ex.moveMouse(__mv[0],__mv[1]);return{content:[{type:"text",text:"Moved to ("+__mv[0]+","+__mv[1]+")"}]}}
case"hold_key":{await ex.holdKey(e.key||"",e.duration||.5);return{content:[{type:"text",text:"Held key"}]}}
case"left_mouse_down":{await ex.mouseDown();return{content:[{type:"text",text:"Mouse down"}]}}
case"left_mouse_up":{await ex.mouseUp();return{content:[{type:"text",text:"Mouse up"}]}}
case"computer_batch":{var __actions=e.actions||[],__completed=[],__failIdx=-1,__failErr;for(var __bi=0;__bi<__actions.length;__bi++){var __ba=__actions[__bi];try{var __br=await __SELF__.handleToolCall(__ba.action||__ba.type,__ba,r);__completed.push({type:__ba.action||__ba.type,result:__br})}catch(__be){__failIdx=__bi;__failErr=__be.message;break}}var __resp={completed:__completed};if(__failIdx>=0){__resp.failed={index:__failIdx,action:__actions[__failIdx].action||__actions[__failIdx].type,error:__failErr};__resp.remaining=__actions.slice(__failIdx+1).map(function(a){return a.action||a.type})}return{content:[{type:"text",text:JSON.stringify(__resp)}]}}
default:return{content:[{type:"text",text:"Unknown action tool: "+t}],isError:!0}
}})}
try{switch(t){
case"screenshot":{var __dlist=await ex.listDisplays();var __primaryIdx=0;for(var __pi=0;__pi<__dlist.length;__pi++){if(__dlist[__pi].isPrimary){__primaryIdx=__dlist[__pi].displayId;break}}var __did=globalThis.__cuPinnedDisplay!==void 0?globalThis.__cuPinnedDisplay:(e.display_number||e.display_id||__primaryIdx);var __actMon=__dlist.find(function(d){return d.displayId===__did})||__dlist[0]||{originX:0,originY:0};globalThis.__cuActiveOrigin={x:__actMon.originX||0,y:__actMon.originY||0};var __ss=await ex.screenshot({displayId:__did});return{content:[{type:"image",data:__ss.base64,mimeType:"image/png"}]}}
case"zoom":{var __zc=__txC(e.coordinate||[960,540]),__sz=e.size||400,__hf=Math.floor(__sz/2),__zdid=globalThis.__cuPinnedDisplay!==void 0?globalThis.__cuPinnedDisplay:null,__zr=await ex.zoom({x:Math.max(0,__zc[0]-__hf),y:Math.max(0,__zc[1]-__hf),w:__sz,h:__sz},1,__zdid);return{content:[{type:"image",data:__zr.base64,mimeType:"image/png"}]}}
case"cursor_position":{var __cp=await ex.getCursorPosition();var __cpr=__untxC(__cp.x,__cp.y);return{content:[{type:"text",text:"("+__cpr[0]+", "+__cpr[1]+")"}]}}
case"wait":{var __ws=Math.min(e.duration||e.seconds||1,30);await new Promise(function(__rv){setTimeout(__rv,__ws*1000)});return{content:[{type:"text",text:"Waited "+__ws+"s"}]}}
case"open_application":{await ex.openApp(e.app||e.application||"");return{content:[{type:"text",text:"Opened app"}]}}
case"switch_display":{var __displays=await ex.listDisplays();var __target=e.display;if(__target==="auto"||!__target){globalThis.__cuPinnedDisplay=void 0;return{content:[{type:"text",text:"Display mode set to auto (follows cursor). Available: "+__displays.map(function(d){return d.label+" ("+d.width+"x"+d.height+")"}).join(", ")}]}}var __found=__displays.find(function(d){return d.label===__target||String(d.displayId)===String(__target)});if(__found){globalThis.__cuPinnedDisplay=__found.displayId;globalThis.__cuActiveOrigin={x:__found.originX||0,y:__found.originY||0};return{content:[{type:"text",text:"Switched to display: "+__found.label+" ("+__found.width+"x"+__found.height+")"}]}}return{content:[{type:"text",text:"Display '"+__target+"' not found. Available: "+__displays.map(function(d){return d.label}).join(", ")}]}}
case"list_granted_applications":{return{content:[{type:"text",text:"All applications are accessible on Linux (no grants needed)"}]}}
case"read_clipboard":{var cb=await ex.readClipboard();return{content:[{type:"text",text:cb}]}}
case"write_clipboard":{await ex.writeClipboard(e.text||"");return{content:[{type:"text",text:"Written to clipboard"}]}}
default:return{content:[{type:"text",text:"Unknown tool: "+t}],isError:!0}
}}catch(err){return{content:[{type:"text",text:"Error: "+err.message}],isError:!0}}
}