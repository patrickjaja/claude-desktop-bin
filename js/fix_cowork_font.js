(function(){
if(window.__coworkFontFixed)return;
if(window.__themeFontOverride)return;
window.__coworkFontFixed=true;
var FONTS={
"sans":"'Anthropic Sans',ui-sans-serif,system-ui,sans-serif,'Apple Color Emoji','Segoe UI Emoji'",
"system":"system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif",
"dyslexia":"OpenDyslexic,'Comic Sans MS',ui-serif,serif,'Comic Sans MS',ui-sans-serif,system-ui,sans-serif"
};
var el=null;
function apply(){
var raw=null;
try{raw=localStorage.getItem("LSS-customStyles:chatFont")}catch(e){}
if(!raw)return remove();
var val;
try{val=JSON.parse(raw).value}catch(e){return remove()}
if(!val||val==="default"||!FONTS[val])return remove();
var ff=FONTS[val];
if(!el){el=document.createElement("style");el.id="__cowork-font-fix";document.head.appendChild(el)}
el.textContent=".font-claude-response-body,.font-claude-response-title{font-family:"+ff+"!important}";
}
function remove(){if(el){el.remove();el=null}}
apply();
var obs=new MutationObserver(function(){apply()});
obs.observe(document.documentElement,{attributes:true,attributeFilter:["class","data-theme","style"]});
window.addEventListener("storage",function(e){if(e.key&&e.key.indexOf("chatFont")!==-1)apply()});
})()
