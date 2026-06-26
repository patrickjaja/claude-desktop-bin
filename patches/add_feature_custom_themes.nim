# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: nim
#
# Custom CSS theme injection for Claude Desktop on Linux (dual-variant).
#
# Reads a JSON config file (~/.config/Claude/claude-desktop-bin.json) at startup
# and injects CSS variable overrides into ALL windows (main chat, Quick Entry,
# Find-in-Page, About) using Electron's stable webContents.insertCSS() API.
#
# DUAL-VARIANT (v1.15962): each theme may be authored as {light:{...},dark:{...}}.
# The patch emits TWO :root var blocks -- a light block on `:root,[data-mode=light]`
# and a dark block on `.darkTheme,[data-mode=dark],.dark` (dark second so it wins on a
# specificity tie). A FLAT theme object (no light/dark keys -- the old schema, also
# the 6 built-ins below) is treated as BOTH light and dark for backward compat.
#
# Derived aliases: after each variant's var list we append --accent-main-*/-secondary-*
# aliases mapping onto the REAL --accent-*/--accent-pro-* tokens (stock v1.15962 has NO
# --accent-main-*), plus --always-black/--always-white, so old custom themes and our
# element overrides keep working.
#
# Spinner: the active theme's optional `spinner` object is serialized to JSON at runtime
# and prepended to the staticRead'd ../js/spinner_injector.js as
#   var __CDB_SPINNER_SPEC = <json|null>;
# then run via wc.executeJavaScript on dom-ready (self-guarding IIFE no-ops if null).
# The spinner animation keyframes ship via insertCSS (appended to __cdb_css).
#
# Break risk: VERY LOW -- No regex on minified app code. Uses only the
# "use strict;" prefix (stable) and standard Electron/Node APIs.

import std/[os, strutils, json]

# Renderer-side spinner installer (owned by the SPINNER agent). Embedded at compile
# time and re-emitted as a JS string literal inside the IIFE; the runtime prepends the
# per-theme spec and hands the whole thing to wc.executeJavaScript().
const SPINNER_INJECTOR_JS = staticRead("../js/spinner_injector.js")

# Head of the injected IIFE: config read + theme resolution + dual-variant CSS build +
# element overrides + font + spinner-keyframes. `__cdb_spinnerSrc` (the injector body)
# is spliced between HEAD and TAIL as a JS string literal (see THEME_INJECTION_JS).
const THEME_INJECTION_JS_HEAD =
  """;(function(){
if(process.platform!=="linux")return;
var _path=require("path"),_fs=require("fs"),_app=require("electron").app;
function __cdb_toCss(v){
if(typeof v==="string")return v;
if(Array.isArray(v))return v.filter(function(x){return typeof x==="string"}).join("\n");
return "";
}
function __cdb_isVarMap(o){
if(!o||typeof o!=="object")return false;
for(var k in o){if(k.indexOf("--")===0)return true}
return false;
}
// Build "k:v !important;..." for every --token in a flat var map, then append the
// derived --accent-main-*/-secondary-* aliases + --always-black/--always-white so
// legacy themes and our element overrides resolve even though stock has no main-*.
function __cdb_block(vars){
var out=[];
for(var k in vars){
if(k.indexOf("--")===0)out.push(k+":"+vars[k]+" !important");
}
out.push("--accent-main-000:var(--accent-000)");
out.push("--accent-main-100:var(--accent-brand)");
out.push("--accent-main-200:var(--accent-200)");
out.push("--accent-main-900:var(--accent-900)");
out.push("--accent-secondary-000:var(--accent-pro-000)");
out.push("--accent-secondary-100:var(--accent-pro-100)");
out.push("--accent-secondary-200:var(--accent-pro-200)");
out.push("--accent-secondary-900:var(--accent-pro-900)");
out.push("--always-black:0 0% 0% !important");
out.push("--always-white:0 0% 100% !important");
return out.join(";");
}
var __cdb_builtins={
"catppuccin-frappe":{"light":{"--bg-000":"0 0.0% 100.0%","--bg-100":"220 23.1% 94.9%","--bg-200":"220 22.0% 92.0%","--bg-300":"220 20.7% 88.6%","--bg-400":"223 15.9% 82.7%","--bg-500":"225 13.6% 76.9%","--text-000":"234 16.0% 35.5%","--text-100":"234 16.0% 35.5%","--text-200":"233 12.8% 41.4%","--text-300":"233 12.8% 41.4%","--text-400":"233 10.4% 46.3%","--text-500":"233 10.4% 46.3%","--accent-brand":"266 85.0% 58.0%","--accent-000":"266 85.0% 58.0%","--accent-100":"266 85.0% 58.0%","--accent-200":"266 85.0% 58.0%","--accent-900":"220 20.7% 88.6%","--accent-pro-000":"231 97.2% 72.0%","--accent-pro-100":"220 91.5% 53.9%","--accent-pro-200":"220 91.5% 53.9%","--accent-pro-900":"220 20.7% 88.6%","--brand-000":"266 85.0% 58.0%","--brand-100":"266 85.0% 58.0%","--brand-200":"266 85.0% 58.0%","--brand-900":"0 0% 0%","--border-100":"234 16% 20%","--border-200":"234 16% 20%","--border-300":"234 16% 20%","--border-400":"234 16% 20%","--danger-000":"347 86.7% 44.1%","--danger-100":"355 76.3% 58.6%","--danger-200":"347 86.7% 44.1%","--danger-900":"351 73.1% 89.8%","--warning-000":"35 77.0% 45.4%","--warning-100":"22 99.2% 52.0%","--warning-200":"35 77.0% 45.4%","--warning-900":"35 68.4% 88.8%","--success-000":"109 57.6% 39.8%","--success-100":"183 73.9% 34.5%","--success-200":"109 57.6% 39.8%","--success-900":"107 42.4% 87.1%","--oncolor-100":"0 0% 100%","--oncolor-200":"0 0% 100%","--oncolor-300":"0 0% 100%","--pictogram-100":"234 16.0% 35.5%","--pictogram-200":"233 12.8% 41.4%","--pictogram-300":"233 10.4% 46.3%","--pictogram-400":"223 15.9% 82.7%","--claude-accent-clay":"#8839ef","--claude-foreground-color":"#4c4f69","--claude-background-color":"#eff1f5","--claude-secondary-color":"#6c6f85","--claude-border":"#8839ef18","--claude-border-300":"#8839ef30","--claude-border-300-more":"#8839ef55","--claude-text-100":"#4c4f69","--claude-text-200":"#5c5f77","--claude-text-400":"#6c6f85","--claude-text-500":"#6c6f85","--claude-description-text":"#5c5f77"},"dark":{"--bg-000":"230 18.8% 26.1%","--bg-100":"229 18.6% 23.1%","--bg-200":"231 18.8% 19.8%","--bg-300":"229 19.5% 17.1%","--bg-400":"231 19.4% 14.1%","--bg-500":"230 20.0% 11.8%","--text-000":"227 70.1% 86.9%","--text-100":"227 70.1% 86.9%","--text-200":"227 43.7% 79.8%","--text-300":"227 43.7% 79.8%","--text-400":"228 29.5% 72.7%","--text-500":"228 29.5% 72.7%","--accent-brand":"277 59.0% 76.1%","--accent-000":"276 61.2% 80.8%","--accent-100":"277 59.0% 76.1%","--accent-200":"277 59.0% 76.1%","--accent-900":"262 25.0% 25.1%","--accent-pro-000":"222 67.5% 84.3%","--accent-pro-100":"222 74.2% 74.1%","--accent-pro-200":"222 74.2% 74.1%","--accent-pro-900":"220 32.2% 23.7%","--brand-000":"276 57.0% 70.8%","--brand-100":"277 59.0% 76.1%","--brand-200":"277 59.0% 76.1%","--brand-900":"0 0% 0%","--border-100":"229 28% 70%","--border-200":"229 28% 70%","--border-300":"229 28% 70%","--border-400":"229 28% 70%","--danger-000":"359 67.8% 70.8%","--danger-100":"359 67.8% 70.8%","--danger-200":"359 67.8% 70.8%","--danger-900":"358 24.5% 19.2%","--warning-000":"40 62.0% 73.1%","--warning-100":"20 79.1% 70.0%","--warning-200":"20 79.1% 70.0%","--warning-900":"42 27.7% 18.4%","--success-000":"96 43.9% 67.8%","--success-100":"96 43.9% 67.8%","--success-200":"96 43.9% 67.8%","--success-900":"97 28.4% 15.9%","--oncolor-100":"229 18.6% 23.1%","--oncolor-200":"229 18.6% 23.1%","--oncolor-300":"229 18.6% 23.1%","--pictogram-100":"227 70.1% 86.9%","--pictogram-200":"227 43.7% 79.8%","--pictogram-300":"228 29.5% 72.7%","--pictogram-400":"230 15.6% 30.2%","--claude-accent-clay":"#ca9ee6","--claude-foreground-color":"#c6d0f5","--claude-background-color":"#303446","--claude-secondary-color":"#a5adce","--claude-border":"#ca9ee618","--claude-border-300":"#ca9ee630","--claude-border-300-more":"#ca9ee655","--claude-text-100":"#c6d0f5","--claude-text-200":"#b5bfe2","--claude-text-400":"#a5adce","--claude-text-500":"#949cbb","--claude-description-text":"#b5bfe2"},"spinner":{"viewBox":"0 0 100 100","animation":"pulse","paths":[{"d":"M26 45 L49 34 L19 13 Z M74 45 L81 13 L51 34 Z M23 55 a 27 27 0 1 0 54 0 a 27 27 0 1 0 -54 0 z"}]}},
"catppuccin-latte":{"light":{"--bg-000":"0 0.0% 100.0%","--bg-100":"220 23.1% 94.9%","--bg-200":"220 22.0% 92.0%","--bg-300":"220 20.7% 88.6%","--bg-400":"223 15.9% 82.7%","--bg-500":"225 13.6% 76.9%","--text-000":"234 16.0% 35.5%","--text-100":"234 16.0% 35.5%","--text-200":"233 12.8% 41.4%","--text-300":"233 12.8% 41.4%","--text-400":"233 10.4% 46.3%","--text-500":"233 10.4% 46.3%","--accent-brand":"266 85.0% 58.0%","--accent-000":"266 85.0% 58.0%","--accent-100":"266 85.0% 58.0%","--accent-200":"266 85.0% 58.0%","--accent-900":"220 20.7% 88.6%","--accent-pro-000":"231 97.2% 72.0%","--accent-pro-100":"220 91.5% 53.9%","--accent-pro-200":"220 91.5% 53.9%","--accent-pro-900":"220 20.7% 88.6%","--brand-000":"266 85.0% 58.0%","--brand-100":"266 85.0% 58.0%","--brand-200":"266 85.0% 58.0%","--brand-900":"0 0% 0%","--border-100":"234 16% 20%","--border-200":"234 16% 20%","--border-300":"234 16% 20%","--border-400":"234 16% 20%","--danger-000":"347 86.7% 44.1%","--danger-100":"355 76.3% 58.6%","--danger-200":"347 86.7% 44.1%","--danger-900":"351 73.1% 89.8%","--warning-000":"35 77.0% 45.4%","--warning-100":"22 99.2% 52.0%","--warning-200":"35 77.0% 45.4%","--warning-900":"35 68.4% 88.8%","--success-000":"109 57.6% 39.8%","--success-100":"183 73.9% 34.5%","--success-200":"109 57.6% 39.8%","--success-900":"107 42.4% 87.1%","--oncolor-100":"0 0% 100%","--oncolor-200":"0 0% 100%","--oncolor-300":"0 0% 100%","--pictogram-100":"234 16.0% 35.5%","--pictogram-200":"233 12.8% 41.4%","--pictogram-300":"233 10.4% 46.3%","--pictogram-400":"223 15.9% 82.7%","--claude-accent-clay":"#8839ef","--claude-foreground-color":"#4c4f69","--claude-background-color":"#eff1f5","--claude-secondary-color":"#6c6f85","--claude-border":"#8839ef18","--claude-border-300":"#8839ef30","--claude-border-300-more":"#8839ef55","--claude-text-100":"#4c4f69","--claude-text-200":"#5c5f77","--claude-text-400":"#6c6f85","--claude-text-500":"#6c6f85","--claude-description-text":"#5c5f77"},"dark":{"--bg-000":"240 19.6% 18.0%","--bg-100":"240 21.1% 14.9%","--bg-200":"240 21.3% 12.0%","--bg-300":"240 19.2% 10.2%","--bg-400":"240 22.7% 8.6%","--bg-500":"240 21.2% 6.5%","--text-000":"226 63.9% 88.0%","--text-100":"226 63.9% 88.0%","--text-200":"227 35.3% 80.0%","--text-300":"227 35.3% 80.0%","--text-400":"228 23.6% 71.8%","--text-500":"228 23.6% 71.8%","--accent-brand":"267 83.5% 81.0%","--accent-000":"266 84.4% 84.9%","--accent-100":"267 83.5% 81.0%","--accent-200":"267 83.5% 81.0%","--accent-900":"256 29.9% 26.3%","--accent-pro-000":"232 97.4% 85.1%","--accent-pro-100":"217 91.9% 75.9%","--accent-pro-200":"217 91.9% 75.9%","--accent-pro-900":"228 32.8% 23.3%","--brand-000":"263 76.6% 74.9%","--brand-100":"267 83.5% 81.0%","--brand-200":"267 83.5% 81.0%","--brand-900":"0 0% 0%","--border-100":"232 28% 72%","--border-200":"232 28% 72%","--border-300":"232 28% 72%","--border-400":"232 28% 72%","--danger-000":"343 81.2% 74.9%","--danger-100":"343 81.2% 74.9%","--danger-200":"343 81.2% 74.9%","--danger-900":"338 32.7% 19.8%","--warning-000":"41 86.0% 83.1%","--warning-100":"23 92.0% 75.5%","--warning-200":"23 92.0% 75.5%","--warning-900":"38 36.7% 19.2%","--success-000":"115 54.1% 76.1%","--success-100":"115 54.1% 76.1%","--success-200":"115 54.1% 76.1%","--success-900":"112 27.1% 16.7%","--oncolor-100":"240 21.1% 14.9%","--oncolor-200":"240 21.1% 14.9%","--oncolor-300":"240 21.1% 14.9%","--pictogram-100":"226 63.9% 88.0%","--pictogram-200":"227 35.3% 80.0%","--pictogram-300":"228 23.6% 71.8%","--pictogram-400":"237 16.2% 22.9%","--claude-accent-clay":"#cba6f7","--claude-foreground-color":"#cdd6f4","--claude-background-color":"#1e1e2e","--claude-secondary-color":"#a6adc8","--claude-border":"#cba6f718","--claude-border-300":"#cba6f730","--claude-border-300-more":"#cba6f755","--claude-text-100":"#cdd6f4","--claude-text-200":"#bac2de","--claude-text-400":"#a6adc8","--claude-text-500":"#9399b2","--claude-description-text":"#bac2de"},"spinner":{"viewBox":"0 0 100 100","animation":"pulse","paths":[{"d":"M23 54 L65 54 L60 84 L28 84 Z M22 87 L66 87 L61 91 L27 91 Z M65 57 A 13 13 0 1 1 65 81 L65 75 A 7 7 0 1 0 65 63 Z M40 50 C45 44 35 40 42 34 C45 28 37 24 40 18 L36 18 C33 24 41 28 38 34 C31 40 41 44 36 50 Z M52 50 C57 44 47 40 54 34 C57 28 49 24 52 18 L48 18 C45 24 53 28 50 34 C43 40 53 44 48 50 Z"}]}},
"catppuccin-macchiato":{"light":{"--bg-000":"0 0.0% 100.0%","--bg-100":"220 23.1% 94.9%","--bg-200":"220 22.0% 92.0%","--bg-300":"220 20.7% 88.6%","--bg-400":"223 15.9% 82.7%","--bg-500":"225 13.6% 76.9%","--text-000":"234 16.0% 35.5%","--text-100":"234 16.0% 35.5%","--text-200":"233 12.8% 41.4%","--text-300":"233 12.8% 41.4%","--text-400":"233 10.4% 46.3%","--text-500":"233 10.4% 46.3%","--accent-brand":"266 85.0% 58.0%","--accent-000":"266 85.0% 58.0%","--accent-100":"266 85.0% 58.0%","--accent-200":"266 85.0% 58.0%","--accent-900":"220 20.7% 88.6%","--accent-pro-000":"231 97.2% 72.0%","--accent-pro-100":"220 91.5% 53.9%","--accent-pro-200":"220 91.5% 53.9%","--accent-pro-900":"220 20.7% 88.6%","--brand-000":"266 85.0% 58.0%","--brand-100":"266 85.0% 58.0%","--brand-200":"266 85.0% 58.0%","--brand-900":"0 0% 0%","--border-100":"234 16% 20%","--border-200":"234 16% 20%","--border-300":"234 16% 20%","--border-400":"234 16% 20%","--danger-000":"347 86.7% 44.1%","--danger-100":"355 76.3% 58.6%","--danger-200":"347 86.7% 44.1%","--danger-900":"351 73.1% 89.8%","--warning-000":"35 77.0% 45.4%","--warning-100":"22 99.2% 52.0%","--warning-200":"35 77.0% 45.4%","--warning-900":"35 68.4% 88.8%","--success-000":"109 57.6% 39.8%","--success-100":"183 73.9% 34.5%","--success-200":"109 57.6% 39.8%","--success-900":"107 42.4% 87.1%","--oncolor-100":"0 0% 100%","--oncolor-200":"0 0% 100%","--oncolor-300":"0 0% 100%","--pictogram-100":"234 16.0% 35.5%","--pictogram-200":"233 12.8% 41.4%","--pictogram-300":"233 10.4% 46.3%","--pictogram-400":"223 15.9% 82.7%","--claude-accent-clay":"#8839ef","--claude-foreground-color":"#4c4f69","--claude-background-color":"#eff1f5","--claude-secondary-color":"#6c6f85","--claude-border":"#8839ef18","--claude-border-300":"#8839ef30","--claude-border-300-more":"#8839ef55","--claude-text-100":"#4c4f69","--claude-text-200":"#5c5f77","--claude-text-400":"#6c6f85","--claude-text-500":"#6c6f85","--claude-description-text":"#5c5f77"},"dark":{"--bg-000":"232 22.2% 21.2%","--bg-100":"232 23.4% 18.4%","--bg-200":"233 23.1% 15.3%","--bg-300":"232 22.4% 13.1%","--bg-400":"236 22.6% 12.2%","--bg-500":"235 24.0% 9.8%","--text-000":"227 68.3% 87.6%","--text-100":"227 68.3% 87.6%","--text-200":"228 39.2% 80.0%","--text-300":"228 39.2% 80.0%","--text-400":"227 26.8% 72.2%","--text-500":"227 26.8% 72.2%","--accent-brand":"267 82.7% 79.6%","--accent-000":"265 83.1% 83.7%","--accent-100":"267 82.7% 79.6%","--accent-200":"267 82.7% 79.6%","--accent-900":"256 30.1% 24.1%","--accent-pro-000":"227 84.6% 84.7%","--accent-pro-100":"220 82.8% 74.9%","--accent-pro-200":"220 82.8% 74.9%","--accent-pro-900":"222 38.1% 22.2%","--brand-000":"265 76.1% 73.7%","--brand-100":"267 82.7% 79.6%","--brand-200":"267 82.7% 79.6%","--brand-900":"0 0% 0%","--border-100":"232 28% 71%","--border-200":"232 28% 71%","--border-300":"232 28% 71%","--border-400":"232 28% 71%","--danger-000":"351 73.9% 72.9%","--danger-100":"351 73.9% 72.9%","--danger-200":"351 73.9% 72.9%","--danger-900":"343 29.9% 19.0%","--warning-000":"40 69.9% 77.8%","--warning-100":"21 85.5% 72.9%","--warning-200":"21 85.5% 72.9%","--warning-900":"39 34.0% 18.4%","--success-000":"105 48.3% 72.0%","--success-100":"105 48.3% 72.0%","--success-200":"105 48.3% 72.0%","--success-900":"108 30.0% 15.7%","--oncolor-100":"232 23.4% 18.4%","--oncolor-200":"232 23.4% 18.4%","--oncolor-300":"232 23.4% 18.4%","--pictogram-100":"227 68.3% 87.6%","--pictogram-200":"228 39.2% 80.0%","--pictogram-300":"227 26.8% 72.2%","--pictogram-400":"230 18.8% 26.1%","--claude-accent-clay":"#c6a0f6","--claude-foreground-color":"#cad3f5","--claude-background-color":"#24273a","--claude-secondary-color":"#a5adcb","--claude-border":"#c6a0f618","--claude-border-300":"#c6a0f630","--claude-border-300-more":"#c6a0f655","--claude-text-100":"#cad3f5","--claude-text-200":"#b8c0e0","--claude-text-400":"#a5adcb","--claude-text-500":"#939ab7","--claude-description-text":"#b8c0e0"},"spinner":{"viewBox":"0 0 100 100","animation":"pulse","paths":[{"d":"M26 45 L49 34 L19 13 Z M74 45 L81 13 L51 34 Z M23 55 a 27 27 0 1 0 54 0 a 27 27 0 1 0 -54 0 z"}]}},
"catppuccin-mocha":{"light":{"--bg-000":"0 0.0% 100.0%","--bg-100":"220 23.1% 94.9%","--bg-200":"220 22.0% 92.0%","--bg-300":"220 20.7% 88.6%","--bg-400":"223 15.9% 82.7%","--bg-500":"225 13.6% 76.9%","--text-000":"234 16.0% 35.5%","--text-100":"234 16.0% 35.5%","--text-200":"233 12.8% 41.4%","--text-300":"233 12.8% 41.4%","--text-400":"233 10.4% 46.3%","--text-500":"233 10.4% 46.3%","--accent-brand":"266 85.0% 58.0%","--accent-000":"266 85.0% 58.0%","--accent-100":"266 85.0% 58.0%","--accent-200":"266 85.0% 58.0%","--accent-900":"220 20.7% 88.6%","--accent-pro-000":"231 97.2% 72.0%","--accent-pro-100":"220 91.5% 53.9%","--accent-pro-200":"220 91.5% 53.9%","--accent-pro-900":"220 20.7% 88.6%","--brand-000":"266 85.0% 58.0%","--brand-100":"266 85.0% 58.0%","--brand-200":"266 85.0% 58.0%","--brand-900":"0 0% 0%","--border-100":"234 16% 20%","--border-200":"234 16% 20%","--border-300":"234 16% 20%","--border-400":"234 16% 20%","--danger-000":"347 86.7% 44.1%","--danger-100":"355 76.3% 58.6%","--danger-200":"347 86.7% 44.1%","--danger-900":"351 73.1% 89.8%","--warning-000":"35 77.0% 45.4%","--warning-100":"22 99.2% 52.0%","--warning-200":"35 77.0% 45.4%","--warning-900":"35 68.4% 88.8%","--success-000":"109 57.6% 39.8%","--success-100":"183 73.9% 34.5%","--success-200":"109 57.6% 39.8%","--success-900":"107 42.4% 87.1%","--oncolor-100":"0 0% 100%","--oncolor-200":"0 0% 100%","--oncolor-300":"0 0% 100%","--pictogram-100":"234 16.0% 35.5%","--pictogram-200":"233 12.8% 41.4%","--pictogram-300":"233 10.4% 46.3%","--pictogram-400":"223 15.9% 82.7%","--claude-accent-clay":"#8839ef","--claude-foreground-color":"#4c4f69","--claude-background-color":"#eff1f5","--claude-secondary-color":"#6c6f85","--claude-border":"#8839ef18","--claude-border-300":"#8839ef30","--claude-border-300-more":"#8839ef55","--claude-text-100":"#4c4f69","--claude-text-200":"#5c5f77","--claude-text-400":"#6c6f85","--claude-text-500":"#6c6f85","--claude-description-text":"#5c5f77"},"dark":{"--bg-000":"240 19.6% 18.0%","--bg-100":"240 21.1% 14.9%","--bg-200":"240 21.3% 12.0%","--bg-300":"240 19.2% 10.2%","--bg-400":"240 22.7% 8.6%","--bg-500":"240 21.2% 6.5%","--text-000":"226 63.9% 88.0%","--text-100":"226 63.9% 88.0%","--text-200":"227 35.3% 80.0%","--text-300":"227 35.3% 80.0%","--text-400":"228 23.6% 71.8%","--text-500":"228 23.6% 71.8%","--accent-brand":"267 83.5% 81.0%","--accent-000":"266 84.4% 84.9%","--accent-100":"267 83.5% 81.0%","--accent-200":"267 83.5% 81.0%","--accent-900":"256 29.9% 26.3%","--accent-pro-000":"232 97.4% 85.1%","--accent-pro-100":"217 91.9% 75.9%","--accent-pro-200":"217 91.9% 75.9%","--accent-pro-900":"228 32.8% 23.3%","--brand-000":"263 76.6% 74.9%","--brand-100":"267 83.5% 81.0%","--brand-200":"267 83.5% 81.0%","--brand-900":"0 0% 0%","--border-100":"232 28% 72%","--border-200":"232 28% 72%","--border-300":"232 28% 72%","--border-400":"232 28% 72%","--danger-000":"343 81.2% 74.9%","--danger-100":"343 81.2% 74.9%","--danger-200":"343 81.2% 74.9%","--danger-900":"338 32.7% 19.8%","--warning-000":"41 86.0% 83.1%","--warning-100":"23 92.0% 75.5%","--warning-200":"23 92.0% 75.5%","--warning-900":"38 36.7% 19.2%","--success-000":"115 54.1% 76.1%","--success-100":"115 54.1% 76.1%","--success-200":"115 54.1% 76.1%","--success-900":"112 27.1% 16.7%","--oncolor-100":"240 21.1% 14.9%","--oncolor-200":"240 21.1% 14.9%","--oncolor-300":"240 21.1% 14.9%","--pictogram-100":"226 63.9% 88.0%","--pictogram-200":"227 35.3% 80.0%","--pictogram-300":"228 23.6% 71.8%","--pictogram-400":"237 16.2% 22.9%","--claude-accent-clay":"#cba6f7","--claude-foreground-color":"#cdd6f4","--claude-background-color":"#1e1e2e","--claude-secondary-color":"#a6adc8","--claude-border":"#cba6f718","--claude-border-300":"#cba6f730","--claude-border-300-more":"#cba6f755","--claude-text-100":"#cdd6f4","--claude-text-200":"#bac2de","--claude-text-400":"#a6adc8","--claude-text-500":"#9399b2","--claude-description-text":"#bac2de"},"spinner":{"viewBox":"0 0 100 100","animation":"pulse","paths":[{"d":"M26 45 L49 34 L19 13 Z M74 45 L81 13 L51 34 Z M23 55 a 27 27 0 1 0 54 0 a 27 27 0 1 0 -54 0 z"}]}},
"nord":{"light":{"--bg-000":"0 0.0% 100.0%","--bg-100":"218 26.7% 94.1%","--bg-200":"218 26.8% 92.0%","--bg-300":"219 26.9% 89.8%","--bg-400":"219 27.9% 88.0%","--bg-500":"218 23.5% 84.1%","--text-000":"220 16.4% 21.6%","--text-100":"220 16.4% 21.6%","--text-200":"220 16.8% 31.6%","--text-300":"220 16.8% 31.6%","--text-400":"220 16.5% 35.7%","--text-500":"220 16.5% 35.7%","--accent-brand":"213 32.0% 48.2%","--accent-000":"213 32.0% 52.2%","--accent-100":"213 32.0% 48.2%","--accent-200":"213 32.0% 48.2%","--accent-900":"219 26.9% 89.8%","--accent-pro-000":"309 19.3% 52.4%","--accent-pro-100":"310 21.1% 44.7%","--accent-pro-200":"310 21.1% 44.7%","--accent-pro-900":"274 26.9% 89.8%","--brand-000":"213 32.0% 52.2%","--brand-100":"213 32.0% 48.2%","--brand-200":"213 32.0% 48.2%","--brand-900":"0 0% 0%","--border-100":"220 18% 28%","--border-200":"220 18% 28%","--border-300":"220 18% 28%","--border-400":"220 18% 28%","--danger-000":"354 42.3% 56.5%","--danger-100":"354 42.3% 56.5%","--danger-200":"355 43.0% 46.1%","--danger-900":"355 44.4% 89.4%","--warning-000":"36 61.5% 42.7%","--warning-100":"14 50.5% 62.7%","--warning-200":"36 67.7% 36.5%","--warning-900":"43 50.0% 87.5%","--success-000":"94 33.0% 36.9%","--success-100":"92 27.8% 64.7%","--success-200":"94 35.8% 31.8%","--success-900":"87 34.3% 86.3%","--oncolor-100":"0 0% 100%","--oncolor-200":"0 0% 100%","--oncolor-300":"0 0% 100%","--pictogram-100":"220 16.4% 21.6%","--pictogram-200":"220 16.8% 31.6%","--pictogram-300":"220 16.5% 35.7%","--pictogram-400":"219 26.9% 89.8%","--claude-accent-clay":"#5477a2","--claude-foreground-color":"#2e3440","--claude-background-color":"#eceff4","--claude-secondary-color":"#4c566a","--claude-border":"#5477a218","--claude-border-300":"#5477a230","--claude-border-300-more":"#5477a255","--claude-text-100":"#2e3440","--claude-text-200":"#434c5e","--claude-text-400":"#4c566a","--claude-text-500":"#4c566a","--claude-description-text":"#434c5e"},"dark":{"--bg-000":"220 16% 26%","--bg-100":"220 16.4% 21.6%","--bg-200":"221 15.7% 20.0%","--bg-300":"220 16.1% 18.2%","--bg-400":"222 16.5% 15.5%","--bg-500":"222 15.6% 12.5%","--text-000":"218 26.7% 94.1%","--text-100":"218 26.7% 94.1%","--text-200":"219 27.9% 88.0%","--text-300":"219 27.9% 88.0%","--text-400":"223 12.5% 71.8%","--text-500":"223 12.5% 71.8%","--accent-brand":"193 43.4% 67.5%","--accent-000":"179 25.1% 64.9%","--accent-100":"193 43.4% 67.5%","--accent-200":"193 43.4% 67.5%","--accent-900":"193 20.0% 22.5%","--accent-pro-000":"311 20.2% 63.1%","--accent-pro-100":"312 16.2% 58.8%","--accent-pro-200":"312 16.2% 58.8%","--accent-pro-900":"280 17.2% 17.1%","--brand-000":"210 34.0% 63.1%","--brand-100":"193 43.4% 67.5%","--brand-200":"193 43.4% 67.5%","--brand-900":"0 0% 0%","--border-100":"218 24% 72%","--border-200":"218 24% 72%","--border-300":"218 24% 72%","--border-400":"218 24% 72%","--danger-000":"354 51.4% 63.7%","--danger-100":"354 42.3% 56.5%","--danger-200":"354 42.3% 56.5%","--danger-900":"350 26.1% 18.0%","--warning-000":"40 70.6% 73.3%","--warning-100":"14 50.5% 62.7%","--warning-200":"14 50.5% 62.7%","--warning-900":"40 30.3% 17.5%","--success-000":"92 27.8% 64.7%","--success-100":"92 27.8% 64.7%","--success-200":"92 27.8% 64.7%","--success-900":"93 27.5% 15.7%","--oncolor-100":"220 16.4% 21.6%","--oncolor-200":"220 16.4% 21.6%","--oncolor-300":"220 16.4% 21.6%","--pictogram-100":"218 26.7% 94.1%","--pictogram-200":"219 27.9% 88.0%","--pictogram-300":"223 12.5% 71.8%","--pictogram-400":"222 16.3% 27.6%","--claude-accent-clay":"#88c0d0","--claude-foreground-color":"#eceff4","--claude-background-color":"#2e3440","--claude-secondary-color":"#9aa0ae","--claude-border":"#88c0d018","--claude-border-300":"#88c0d030","--claude-border-300-more":"#88c0d055","--claude-text-100":"#eceff4","--claude-text-200":"#d8dee9","--claude-text-400":"#9aa0ae","--claude-text-500":"#9aa0ae","--claude-description-text":"#b9bfcb"},"spinner":{"viewBox":"0 0 100 100","animation":"spin","paths":[{"d":"M50 53.2 L90 53.2 L90 46.8 L50 46.8 Z M67.92 51.2 L72.42 58.99 L76.58 56.59 L72.08 48.8 Z M72.08 51.2 L76.58 43.41 L72.42 41.01 L67.92 48.8 Z M77.92 51.2 L82.42 58.99 L86.58 56.59 L82.08 48.8 Z M82.08 51.2 L86.58 43.41 L82.42 41.01 L77.92 48.8 Z M47.23 51.6 L67.23 86.24 L72.77 83.04 L52.77 48.4 Z M57.92 66.12 L53.42 73.91 L57.58 76.31 L62.08 68.52 Z M60 69.72 L69 69.72 L69 64.92 L60 64.92 Z M62.92 74.78 L58.42 82.57 L62.58 84.97 L67.08 77.18 Z M65 78.38 L74 78.38 L74 73.58 L65 73.58 Z M47.23 48.4 L27.23 83.04 L32.77 86.24 L52.77 51.6 Z M40 64.92 L31 64.92 L31 69.72 L40 69.72 Z M37.92 68.52 L42.42 76.31 L46.58 73.91 L42.08 66.12 Z M35 73.58 L26 73.58 L26 78.38 L35 78.38 Z M32.92 77.18 L37.42 84.97 L41.58 82.57 L37.08 74.78 Z M50 46.8 L10 46.8 L10 53.2 L50 53.2 Z M32.08 48.8 L27.58 41.01 L23.42 43.41 L27.92 51.2 Z M27.92 48.8 L23.42 56.59 L27.58 58.99 L32.08 51.2 Z M22.08 48.8 L17.58 41.01 L13.42 43.41 L17.92 51.2 Z M17.92 48.8 L13.42 56.59 L17.58 58.99 L22.08 51.2 Z M52.77 48.4 L32.77 13.76 L27.23 16.96 L47.23 51.6 Z M42.08 33.88 L46.58 26.09 L42.42 23.69 L37.92 31.48 Z M40 30.28 L31 30.28 L31 35.08 L40 35.08 Z M37.08 25.22 L41.58 17.43 L37.42 15.03 L32.92 22.82 Z M35 21.62 L26 21.62 L26 26.42 L35 26.42 Z M52.77 51.6 L72.77 16.96 L67.23 13.76 L47.23 48.4 Z M60 35.08 L69 35.08 L69 30.28 L60 30.28 Z M62.08 31.48 L57.58 23.69 L53.42 26.09 L57.92 33.88 Z M65 26.42 L74 26.42 L74 21.62 L65 21.62 Z M67.08 22.82 L62.58 15.03 L58.42 17.43 L62.92 25.22 Z M44 50 a 6 6 0 1 0 12 0 a 6 6 0 1 0 -12 0 z"}]}},
"super-mario":{"light":{"--bg-000":"204 100% 96%","--bg-100":"203 92% 90%","--bg-200":"202 85% 84%","--bg-300":"201 78% 78%","--bg-400":"200 72% 71%","--bg-500":"200 68% 64%","--text-000":"222 66% 13%","--text-100":"222 66% 13%","--text-200":"220 52.0% 26.0%","--text-300":"220 52.0% 26.0%","--text-400":"218 38.0% 38.0%","--text-500":"218 38.0% 38.0%","--accent-brand":"1 79.0% 49.0%","--accent-000":"8 85% 46%","--accent-100":"8 85% 42%","--accent-200":"8 85% 42%","--accent-900":"16 90% 88%","--accent-pro-000":"211 90.0% 44.0%","--accent-pro-100":"211 90.0% 40.0%","--accent-pro-200":"211 90.0% 40.0%","--accent-pro-900":"211 80% 88%","--brand-000":"1 79.0% 49.0%","--brand-100":"1 79.0% 49.0%","--brand-200":"1 79.0% 49.0%","--brand-900":"0 0% 0%","--border-100":"211 70% 32%","--border-200":"211 70% 32%","--border-300":"211 70% 32%","--border-400":"211 70% 32%","--danger-000":"0 100.0% 38.0%","--danger-100":"0 80% 50%","--danger-200":"0 100.0% 33.3%","--danger-900":"0 70% 90%","--warning-000":"33 100.0% 30.0%","--warning-100":"40 100.0% 45.0%","--warning-200":"33 100.0% 27.0%","--warning-900":"45 95% 84%","--success-000":"133 80.0% 26.0%","--success-100":"133 75% 32%","--success-200":"133 80.0% 23.0%","--success-900":"133 55% 86%","--oncolor-100":"0 0% 100%","--oncolor-200":"0 0% 100%","--oncolor-300":"0 0% 100%","--pictogram-100":"222 66% 13%","--pictogram-200":"220 52.0% 26.0%","--pictogram-300":"211 60% 38%","--pictogram-400":"202 85% 84%","--claude-accent-clay":"#e52421","--claude-foreground-color":"#0a1733","--claude-background-color":"#5c94fc","--claude-secondary-color":"#2a4a8f","--claude-border":"#1f4ba318","--claude-border-300":"#1f4ba330","--claude-border-300-more":"#1f4ba355","--claude-text-100":"#0a1733","--claude-text-200":"#1d3566","--claude-text-400":"#2a4a8f","--claude-text-500":"#2a4a8f","--claude-description-text":"#1d3566"},"dark":{"--bg-000":"20 32% 15%","--bg-100":"20 36% 11%","--bg-200":"18 40% 8.5%","--bg-300":"16 42% 6.5%","--bg-400":"16 44% 4%","--bg-500":"16 46% 2.5%","--text-000":"40 60% 96%","--text-100":"40 60% 96%","--text-200":"38 35% 83%","--text-300":"38 35% 83%","--text-400":"34 24.0% 66.0%","--text-500":"34 24.0% 66.0%","--accent-brand":"6 90.0% 44.0%","--accent-000":"8 92% 46%","--accent-100":"6 90% 44%","--accent-200":"6 90% 44%","--accent-900":"16 70% 22%","--accent-pro-000":"205 100% 72%","--accent-pro-100":"205 95% 62%","--accent-pro-200":"205 95% 62%","--accent-pro-900":"210 70% 24%","--brand-000":"2 88% 60%","--brand-100":"2 84.0% 56.0%","--brand-200":"2 84.0% 56.0%","--brand-900":"0 0% 0%","--border-100":"36 38% 70%","--border-200":"36 38% 70%","--border-300":"36 38% 70%","--border-400":"36 38% 70%","--danger-000":"0 95% 72%","--danger-100":"0 85% 66%","--danger-200":"0 85% 66%","--danger-900":"0 60% 26%","--warning-000":"45 100.0% 56.0%","--warning-100":"45 100.0% 52.0%","--warning-200":"45 100.0% 52.0%","--warning-900":"42 80% 18%","--success-000":"130 70% 55%","--success-100":"130 65% 48%","--success-200":"130 65% 48%","--success-900":"130 55% 16%","--oncolor-100":"0 0% 100%","--oncolor-200":"0 0% 100%","--oncolor-300":"0 0% 100%","--pictogram-100":"40 60% 96%","--pictogram-200":"38 35% 83%","--pictogram-300":"34 24.0% 66.0%","--pictogram-400":"20 32% 22%","--claude-accent-clay":"#ef3a36","--claude-foreground-color":"#fbf3e6","--claude-background-color":"#2a1a12","--claude-secondary-color":"#c9a888","--claude-border":"#f5d03d18","--claude-border-300":"#f5d03d30","--claude-border-300-more":"#f5d03d55","--claude-text-100":"#fbf3e6","--claude-text-200":"#e8d6bf","--claude-text-400":"#c9a888","--claude-text-500":"#c9a888","--claude-description-text":"#f5d03d"},"spinner":{"viewBox":"0 0 100 100","animation":"bounce","paths":[{"d":"M50 10c-21 0-38 15-38 35 0 6 3 10 8 12 2 1 4 2 4 5v16c0 5 4 9 9 9h34c5 0 9-4 9-9V67c0-3 2-4 4-5 5-2 8-6 8-12 0-20-17-35-38-35z","fill":"#3A2A1A"},{"d":"M50 14c-19 0-34 13-34 31 0 5 3 8 7 9 3 1 6 1 9 1h36c3 0 6 0 9-1 4-1 7-4 7-9 0-18-15-31-34-31z","fill":"#E52521"},{"d":"M30 56h40v16c0 4-3 7-7 7H37c-4 0-7-3-7-7V56z","fill":"#FAD9C0"},{"d":"M38 30a8 8 0 1 0 0.01 0z","fill":"#FFFFFF"},{"d":"M57 22a5 5 0 1 0 0.01 0z","fill":"#FFFFFF"},{"d":"M68 36a6 6 0 1 0 0.01 0z","fill":"#FFFFFF"},{"d":"M42 64a3 3 0 1 0 0.01 0z","fill":"#3A2A1A"},{"d":"M58 64a3 3 0 1 0 0.01 0z","fill":"#3A2A1A"}]}},
"sweet":{"light":{"--bg-000":"0 0% 100%","--bg-100":"315 60% 98%","--bg-200":"300 45% 96%","--bg-300":"295 40% 94%","--bg-400":"290 35% 91%","--bg-500":"288 30% 88%","--text-000":"295 55.0% 18.0%","--text-100":"295 55.0% 18.0%","--text-200":"290 40.0% 32.0%","--text-300":"290 40.0% 32.0%","--text-400":"290 25.0% 45.0%","--text-500":"290 25.0% 45.0%","--accent-brand":"320 85.0% 46.0%","--accent-000":"320 85.0% 45.0%","--accent-100":"320 85.0% 46.0%","--accent-200":"320 85.0% 46.0%","--accent-900":"315 50% 92%","--accent-pro-000":"275 70.0% 52.0%","--accent-pro-100":"275 70.0% 48.0%","--accent-pro-200":"275 70.0% 48.0%","--accent-pro-900":"275 50% 92%","--brand-000":"320 85.0% 48.0%","--brand-100":"320 85.0% 46.0%","--brand-200":"320 85.0% 46.0%","--brand-900":"0 0% 0%","--border-100":"300 30% 28%","--border-200":"300 30% 28%","--border-300":"300 30% 28%","--border-400":"300 30% 28%","--danger-000":"350 80.0% 45.0%","--danger-100":"350 75% 55%","--danger-200":"350 80.0% 42.0%","--danger-900":"350 60% 92%","--warning-000":"35 95.0% 38.0%","--warning-100":"35 90% 50%","--warning-200":"35 95.0% 35.0%","--warning-900":"40 70% 90%","--success-000":"145 75.0% 32.0%","--success-100":"145 60% 42%","--success-200":"145 75.0% 28.0%","--success-900":"145 50% 90%","--oncolor-100":"0 0% 100%","--oncolor-200":"0 0% 100%","--oncolor-300":"0 0% 100%","--pictogram-100":"295 55.0% 18.0%","--pictogram-200":"290 40.0% 32.0%","--pictogram-300":"290 25.0% 45.0%","--pictogram-400":"300 30% 88%","--claude-accent-clay":"#d91297","--claude-foreground-color":"#431547","--claude-background-color":"#fdf7fb","--claude-secondary-color":"#86568f","--claude-border":"#d9129718","--claude-border-300":"#d9129730","--claude-border-300-more":"#d9129755","--claude-text-100":"#431547","--claude-text-200":"#673172","--claude-text-400":"#86568f","--claude-text-500":"#86568f","--claude-description-text":"#673172"},"dark":{"--bg-000":"288 40% 16%","--bg-100":"288 33% 12%","--bg-200":"290 30% 9%","--bg-300":"290 32% 7%","--bg-400":"285 45% 4.5%","--bg-500":"285 55% 3%","--text-000":"300 100% 98%","--text-100":"300 100% 98%","--text-200":"312 90% 86%","--text-300":"312 90% 86%","--text-400":"300 30.0% 70.0%","--text-500":"300 30.0% 70.0%","--accent-brand":"309 100% 76%","--accent-000":"309 100% 84%","--accent-100":"309 100% 76%","--accent-200":"309 100% 76%","--accent-900":"290 70% 28%","--accent-pro-000":"280 100% 85%","--accent-pro-100":"280 80% 72%","--accent-pro-200":"280 80% 72%","--accent-pro-900":"280 50% 22%","--brand-000":"309 100% 65%","--brand-100":"309 100% 76%","--brand-200":"309 100% 76%","--brand-900":"0 0% 0%","--border-100":"300 40% 80%","--border-200":"300 40% 80%","--border-300":"300 40% 80%","--border-400":"300 40% 80%","--danger-000":"0 90% 72%","--danger-100":"0 80% 68%","--danger-200":"0 80% 68%","--danger-900":"0 60% 26%","--warning-000":"45 100% 75%","--warning-100":"38 95% 64%","--warning-200":"38 95% 64%","--warning-900":"40 60% 24%","--success-000":"140 70% 75%","--success-100":"140 55% 62%","--success-200":"140 55% 62%","--success-900":"140 45% 22%","--oncolor-100":"290 60.0% 10.0%","--oncolor-200":"290 60.0% 10.0%","--oncolor-300":"290 60.0% 10.0%","--pictogram-100":"300 100% 98%","--pictogram-200":"312 90% 86%","--pictogram-300":"300 30.0% 70.0%","--pictogram-400":"290 30% 24%","--claude-accent-clay":"#ff7ae6","--claude-foreground-color":"#fff5ff","--claude-background-color":"#251529","--claude-secondary-color":"#c99cc9","--claude-border":"#ff7ae618","--claude-border-300":"#ff7ae630","--claude-border-300-more":"#ff7ae655","--claude-text-100":"#fff5ff","--claude-text-200":"#fbbbef","--claude-text-400":"#c99cc9","--claude-text-500":"#c99cc9","--claude-description-text":"#f5a3e4"},"spinner":{"viewBox":"0 0 100 100","animation":"spin","paths":[{"d":"M50 50 C74.8 30 50 10 50 10 C50 10 25.2 30 50 50 Z M50 50 C76.68 67.41 88.04 37.64 88.04 37.64 C88.04 37.64 61.36 20.23 50 50 Z M50 50 C41.69 80.76 73.51 82.36 73.51 82.36 C73.51 82.36 81.82 51.6 50 50 Z M50 50 C18.18 51.6 26.49 82.36 26.49 82.36 C26.49 82.36 58.31 80.76 50 50 Z M50 50 C38.64 20.23 11.96 37.64 11.96 37.64 C11.96 37.64 23.32 67.41 50 50 Z M34 50 a 16 16 0 1 0 32 0 a 16 16 0 1 0 -32 0 z"}]}}
};
// nordic is an alias for the nord built-in (CONTRACT 5). Add more aliases here as needed.
var __cdb_aliases={"nordic":"nord"};
var __cdb_css="";
var __cdb_fontFlag=false;
var __cdb_spinnerJson="null";
var __cdb_marker="__cdb_dualvariant";
var __cdb_cfgPath=_path.join(_app.getPath("userData"),"claude-desktop-bin.json");
try{
console.log("[CustomThemes] Reading config: "+__cdb_cfgPath);
var __cdb_cfg=JSON.parse(_fs.readFileSync(__cdb_cfgPath,"utf8"));
var __cdb_name=__cdb_cfg.activeTheme;
if(!__cdb_name){console.log("[CustomThemes] No activeTheme set, skipping");return}
if(__cdb_aliases[__cdb_name]){console.log("[CustomThemes] Alias '"+__cdb_name+"' -> '"+__cdb_aliases[__cdb_name]+"'");__cdb_name=__cdb_aliases[__cdb_name]}
console.log("[CustomThemes] Active theme: "+__cdb_name);
var __cdb_customThemes=__cdb_cfg.themes||{};
var __cdb_theme=null,__cdb_src="";
if(__cdb_customThemes[__cdb_name]){__cdb_theme=__cdb_customThemes[__cdb_name];__cdb_src="custom"}
else if(__cdb_builtins[__cdb_name]){__cdb_theme=__cdb_builtins[__cdb_name];__cdb_src="builtin"}
if(!__cdb_theme){
// LOUD fallback (CONTRACT 5): do not silently succeed.
var __cdb_validBuiltins=Object.keys(__cdb_builtins).concat(Object.keys(__cdb_aliases)).join(", ");
console.log("%c[CustomThemes] THEME NOT FOUND: '"+__cdb_name+"'","color:#ff5555;font-weight:bold");
console.log("[CustomThemes] Not in config.themes and not a built-in. Valid built-in names: "+__cdb_validBuiltins);
console.log("[CustomThemes] Define it under \"themes\" in "+__cdb_cfgPath+" or pick a valid built-in. Nothing applied.");
return;
}
// Resolve light/dark variants. Dual-variant -> use each; flat map -> same for both.
var __cdb_lightVars,__cdb_darkVars;
if(__cdb_theme.light||__cdb_theme.dark){
__cdb_lightVars=__cdb_theme.light||__cdb_theme.dark;
__cdb_darkVars=__cdb_theme.dark||__cdb_theme.light;
}else if(__cdb_isVarMap(__cdb_theme)){
__cdb_lightVars=__cdb_theme;
__cdb_darkVars=__cdb_theme;
}else{
console.log("[CustomThemes] Theme '"+__cdb_name+"' has neither light/dark variants nor --token keys; nothing applied");
return;
}
var __cdb_lightBlock=__cdb_block(__cdb_lightVars);
var __cdb_darkBlock=__cdb_block(__cdb_darkVars);
// Emit light first, dark second so dark wins on a specificity tie (both single-class/attr).
__cdb_css=":root,[data-mode=light]{"+__cdb_lightBlock+"}";
__cdb_css+=".darkTheme,[data-mode=dark],.dark{"+__cdb_darkBlock+"}";
"""

# Tail of the IIFE: element overrides (reference semantic tokens, mode-agnostic), the
# dark-only decorative glow block, chatFont, customCss, spinner spec extraction + build,
# spinner keyframes, then the web-contents-created/dom-ready injection hook.
const THEME_INJECTION_JS_TAIL =
  """
// Element overrides (emit ONCE; reference semantic tokens so they are mode-correct).
__cdb_css+=""
+"html,body{color:var(--claude-foreground-color)!important}"
+"#root,[id=root]{background:hsl(var(--bg-000))!important}"
+".dframe-sidebar{background-color:hsl(var(--bg-200))!important}"
+".dframe-content,.dframe-main,main.dframe-main{background-color:hsl(var(--bg-100))!important}"
+".dframe-root{--df-z1:var(--bg-100)!important;--df-z2:var(--bg-200)!important;--df-sidebar-bg:hsl(var(--bg-200))!important;--df-surface-primary:hsl(var(--bg-100))!important}"
+"[data-darker] .dframe-sidebar{background-color:hsl(var(--bg-300))!important}"
+":root,.cds-root,.epitaxy-root,[data-mode=dark],[data-mode=light]{--cds-page-bg:hsl(var(--bg-200))!important;--cds-surface-0:hsl(var(--bg-200))!important;--cds-surface-1:hsl(var(--bg-100))!important;--cds-surface-2:hsl(var(--bg-100))!important;--cds-surface-3:hsl(var(--bg-000))!important;--cds-surface-panel:hsl(var(--bg-100))!important;--cds-surface-popover:hsl(var(--bg-000))!important;--surface-primary:hsl(var(--bg-100))!important;--surface-primary-elevated:hsl(var(--bg-000))!important;--surface-popover:hsl(var(--bg-000))!important;--surface-panel:hsl(var(--bg-100))!important;--surface-hud:hsl(var(--bg-200))!important;--cds-text-primary:hsl(var(--text-000))!important;--cds-text-secondary:hsl(var(--text-200))!important;--cds-text-muted:hsl(var(--text-400))!important;--cds-border:hsl(var(--border-200) / 0.18)!important;--cds-clay:hsl(var(--accent-brand))!important}"
+".epitaxy-top-scrim{background:linear-gradient(hsl(var(--bg-100)),transparent)!important}"
+".epitaxy-bottom-scrim{background:linear-gradient(transparent,hsl(var(--bg-100)))!important}"
+".bg-white{background-color:hsl(var(--bg-000))!important}"
+".text-black{color:hsl(var(--text-000))!important}"
+".container{background:linear-gradient(to bottom,hsl(var(--bg-100)),hsl(var(--bg-000)))!important}"
+".container:before{border-color:hsl(var(--border-300) / 0.3)!important}"
+".input-box textarea{color:var(--claude-foreground-color)!important}"
+".input-box textarea::placeholder{color:var(--claude-text-500)!important}"
+".secondary{color:var(--claude-secondary-color)!important}"
+"input:not([type=checkbox]):not([type=radio]):not([type=range]):not([type=color]),textarea,[contenteditable=true],.ProseMirror{background:transparent!important;color:hsl(var(--text-000))!important;border-color:transparent!important}"
+"[type=text]:focus,[type=email]:focus,[type=url]:focus,[type=password]:focus,[type=number]:focus,[type=search]:focus,textarea:focus,select:focus,[multiple]:focus{--tw-ring-color:hsl(var(--accent-100))!important;border-color:hsl(var(--accent-100))!important}"
+"::placeholder{color:hsl(var(--text-400))!important}"
+"[role=dialog],[role=menu],[role=listbox],[role=tooltip]{background:hsl(var(--bg-100))!important;color:hsl(var(--text-000))!important;border-color:hsl(var(--border-200) / 0.18)!important}"
+"hr{border-color:hsl(var(--border-200) / 0.25)!important}"
+"[type=checkbox]:checked{background-color:hsl(var(--accent-brand))!important;border-color:hsl(var(--accent-brand))!important}"
+"::selection{background:hsl(var(--accent-brand) / 0.3)!important}"
+"*{scrollbar-width:auto!important}"
+"::-webkit-scrollbar{width:6px!important;height:6px!important}"
+"::-webkit-scrollbar-thumb{background:hsl(var(--accent-brand) / 0.5)!important;border-radius:3px!important}"
+"::-webkit-scrollbar-thumb:hover{background:hsl(var(--accent-brand) / 0.7)!important}"
+"::-webkit-scrollbar-track{background:transparent!important}"
+"svg{color:inherit}"
+".nc-drag{color:hsl(var(--text-000))!important}"
+"a,button,[role=tab],[role=menuitem]{transition:background-color .15s ease,box-shadow .15s ease,border-color .15s ease!important}"
+".darkTheme [role=dialog],[data-mode=dark] [role=dialog]{box-shadow:0 0 0 1px hsl(var(--accent-brand) / 0.35),0 12px 40px rgba(0,0,0,0.5),0 0 30px hsl(var(--accent-brand) / 0.1)!important}"
+".darkTheme [role=menu],.darkTheme [role=listbox],[data-mode=dark] [role=menu],[data-mode=dark] [role=listbox]{box-shadow:0 0 0 1px hsl(var(--accent-brand) / 0.3),0 8px 24px rgba(0,0,0,0.4)!important}"
+".darkTheme button:not([disabled]):hover,[data-mode=dark] button:not([disabled]):hover{box-shadow:0 0 12px hsl(var(--accent-brand) / 0.3)!important}";
var __cdb_font=(__cdb_theme&&__cdb_theme.chatFont)||(__cdb_lightVars&&__cdb_lightVars.chatFont)||(__cdb_cfg.chatFont);
if(__cdb_font){
__cdb_css+="html .font-claude-response-body,html .font-claude-response-title,html .font-claude-response,[data-user-message-bubble],[data-user-message-bubble] *{font-family:"+__cdb_font+"!important}";
__cdb_css+=":root{--theme-font-override:1}";
__cdb_fontFlag=true;
console.log("[CustomThemes] Font override: "+__cdb_font);
}
// customCss: top-level and per-theme (string or array). Supported as before.
var __cdb_extra=__cdb_toCss(__cdb_cfg.customCss);
var __cdb_themeExtra=__cdb_toCss(__cdb_theme.customCss)||__cdb_toCss(__cdb_lightVars&&__cdb_lightVars.customCss);
if(__cdb_extra)__cdb_css+="\n"+__cdb_extra;
if(__cdb_themeExtra)__cdb_css+="\n"+__cdb_themeExtra;
if(__cdb_extra||__cdb_themeExtra)console.log("[CustomThemes] customCss appended ("+((__cdb_extra?__cdb_extra.length:0)+(__cdb_themeExtra?__cdb_themeExtra.length:0))+" chars)");
// Spinner spec: read the active theme's `spinner` object (per-theme or flat-shared).
var __cdb_spinnerSpec=(__cdb_theme&&__cdb_theme.spinner)||(__cdb_lightVars&&__cdb_lightVars.spinner)||null;
if(__cdb_spinnerSpec){
try{__cdb_spinnerJson=JSON.stringify(__cdb_spinnerSpec)}catch(e){__cdb_spinnerJson="null"}
}
if(__cdb_spinnerJson&&__cdb_spinnerJson!=="null"){
// Spinner animation keyframes ship via insertCSS (SPINNER_INJECTION_NOTES 4).
__cdb_css+="@keyframes cdbSpin{to{transform:rotate(360deg)}}";
__cdb_css+="@keyframes cdbBounce{0%,100%{transform:translateY(0)}50%{transform:translateY(-12%)}}";
__cdb_css+="@keyframes cdbPulse{0%,100%{opacity:1}50%{opacity:.45}}";
__cdb_css+="svg[data-cdb-spinner].cdb-anim-spin{animation:cdbSpin 1s linear infinite;transform-origin:50% 50%;transform-box:fill-box}";
__cdb_css+="svg[data-cdb-spinner].cdb-anim-bounce{animation:cdbBounce .8s ease-in-out infinite;transform-origin:50% 50%;transform-box:fill-box}";
__cdb_css+="svg[data-cdb-spinner].cdb-anim-pulse{animation:cdbPulse 1.2s ease-in-out infinite}";
console.log("[CustomThemes] Spinner spec present ("+__cdb_spinnerJson.length+" chars JSON)");
}
console.log("[CustomThemes] Loaded "+__cdb_src+" theme '"+__cdb_name+"' (dual-variant) with element overrides");
}catch(e){
if(e.code==="ENOENT"){console.log("[CustomThemes] No config file found at "+__cdb_cfgPath+", skipping")}
else{console.log("[CustomThemes] Error reading config: "+e.message)}
}
if(!__cdb_css)return;
// Build the spinner script: prepend the per-theme spec to the staticRead injector body.
// __cdb_spinnerSrc is baked in by Nim below as a JS string literal.
var __cdb_spinnerScript="var __CDB_SPINNER_SPEC="+__cdb_spinnerJson+";\n"+__cdb_spinnerSrc;
_app.on("web-contents-created",function(_ev,wc){
wc.on("dom-ready",function(){
try{
var url=wc.getURL()||"";
if(url.indexOf("devtools://")===0)return;
if(url.indexOf("http://localhost")===0||url.indexOf("http://127.0.0.1")===0||url.indexOf("https://localhost")===0)return;
wc.insertCSS(__cdb_css);
var __cdb_postJs="";
if(__cdb_fontFlag)__cdb_postJs+="window.__themeFontOverride=true;\n";
__cdb_postJs+=__cdb_spinnerScript;
wc.executeJavaScript(__cdb_postJs).catch(function(){});
console.log("[CustomThemes] Injected CSS+JS into "+url);
}catch(e){console.log("[CustomThemes] insertCSS error: "+e.message)}
});
});
})();"""

# Assemble the full IIFE, splicing the staticRead'd spinner injector in as a JS string
# literal (escapeJson yields a quoted, fully-escaped literal suitable for executeJavaScript).
const THEME_INJECTION_JS =
  THEME_INJECTION_JS_HEAD & "\nvar __cdb_spinnerSrc=" & escapeJson(SPINNER_INJECTOR_JS) &
  ";\n" & THEME_INJECTION_JS_TAIL

proc apply*(input: string): string =
  result = input

  # Idempotency (Rule 6): assert the NEW dual-variant end-state is present, not merely
  # that the old build is gone. The marker string is emitted as `var __cdb_marker=...`
  # AND only this dual-variant build constructs the light/dark block pair.
  let marker = "__cdb_dualvariant"
  if marker in result:
    echo "  [INFO] Dual-variant theme injection already applied (marker present)"
    echo "  [PASS] No changes needed (already patched)"
    return

  # Inject right after "use strict"; at the top of the file
  let strictPrefix = "\"use strict\";"
  if result.startsWith(strictPrefix):
    result = strictPrefix & THEME_INJECTION_JS & result[strictPrefix.len .. ^1]
    echo "  [OK] Dual-variant theme injection IIFE inserted after \"use strict\""
  else:
    result = THEME_INJECTION_JS & result
    echo "  [OK] Dual-variant theme injection IIFE prepended"

  # Positive end-state assertion: the marker we introduced must now be in the output.
  if marker notin result:
    echo "  [FAIL] Dual-variant marker missing after injection -- aborting"
    quit(1)

when isMainModule:
  if paramCount() != 1:
    echo "Usage: add_feature_custom_themes <path_to_index.js>"
    quit(1)

  let filePath = paramStr(1)
  echo "=== Patch: add_feature_custom_themes ==="
  echo "  Target: " & filePath

  if not fileExists(filePath):
    echo "  [FAIL] File not found: " & filePath
    quit(1)

  let input = readFile(filePath)
  let output = apply(input)

  if output != input:
    writeFile(filePath, output)
    echo "  [PASS] Custom theme support added"
  else:
    echo "  [WARN] No changes made"
