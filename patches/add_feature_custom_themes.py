#!/usr/bin/env python3
# @patch-target: app.asar.contents/.vite/build/index.js
# @patch-type: python
"""
Custom CSS theme injection for Claude Desktop on Linux.

Reads a JSON config file (~/.config/Claude/claude-desktop-bin.json) at startup
and injects CSS variable overrides into ALL windows (main chat, Quick Entry,
Find-in-Page, About) using Electron's stable webContents.insertCSS() API.

Config format:
  {
    "activeTheme": "nord",          // built-in name or key in "themes"
    "themes": {                     // optional custom themes
      "my-theme": {
        "--bg-000": "220 17% 20%",  // HSL components (Tailwind format)
        "--text-000": "219 28% 88%"
      }
    }
  }

Ships 6 built-in themes: sweet, nord, catppuccin-mocha, catppuccin-frappe,
catppuccin-latte, catppuccin-macchiato.

Theming architecture:
  - CSS variables are the primary mechanism. Tailwind compiles to
    hsl(var(--bg-000)) etc., so overriding variables themes all utility classes.
  - Legacy --claude-* hex variables control renderer windows (title bar,
    Quick Entry, Find-in-Page, About).
  - Quick Entry has hardcoded rgba() gradients that need explicit overrides.
  - Prose/typography uses hardcoded hex colors that need --tw-prose-* overrides.

Overrides apply with !important regardless of Light/Dark/Auto mode.
Themes ALL windows: main chat (claude.ai), Quick Entry, Find-in-Page, About.
Requires restart to apply changes (no file watcher).

Break risk: VERY LOW — No regex on minified app code. Uses only the
"use strict;" prefix (stable) and standard Electron/Node APIs.

Usage: python3 add_feature_custom_themes.py <path_to_index.js>
"""

import sys
import os


# JavaScript IIFE injected after "use strict;" in index.js.
# Reads config, builds CSS string, injects via insertCSS on dom-ready.
THEME_INJECTION_JS = b""";(function(){
if(process.platform!=="linux")return;
var _path=require("path"),_fs=require("fs"),_app=require("electron").app;
var __cdb_builtins={
"sweet":{
"--bg-000":"285 50% 8%","--bg-100":"288 29% 17%","--bg-200":"300 26% 19%","--bg-300":"290 25% 14%","--bg-400":"285 50% 5%","--bg-500":"285 60% 3%",
"--text-000":"300 100% 98%","--text-100":"300 100% 98%","--text-200":"312 100% 85%","--text-300":"312 100% 85%","--text-400":"300 17% 65%","--text-500":"300 15% 55%",
"--accent-brand":"309 100% 73%","--accent-main-000":"290 100% 85%","--accent-main-100":"290 100% 76%","--accent-main-200":"309 100% 73%","--accent-main-900":"290 80% 30%",
"--accent-secondary-000":"280 100% 79%","--accent-secondary-100":"280 63% 63%","--accent-secondary-200":"280 60% 50%","--accent-secondary-900":"280 50% 25%",
"--accent-pro-000":"290 100% 85%","--accent-pro-100":"290 100% 76%","--accent-pro-200":"280 63% 63%","--accent-pro-900":"280 50% 25%",
"--border-100":"290 20% 20%","--border-200":"290 20% 20%","--border-300":"300 23% 25%","--border-400":"300 18% 30%",
"--danger-000":"326 100% 66%","--danger-100":"326 100% 58%","--danger-200":"326 100% 48%","--danger-900":"326 80% 22%",
"--warning-000":"300 100% 77%","--warning-100":"300 100% 65%","--warning-200":"300 80% 50%","--warning-900":"300 60% 25%",
"--success-000":"136 100% 85%","--success-100":"136 60% 60%","--success-200":"136 45% 45%","--success-900":"136 40% 20%",
"--oncolor-100":"0 0% 100%","--oncolor-200":"300 100% 98%","--oncolor-300":"300 100% 95%",
"--accent-000":"309 100% 80%","--accent-100":"309 100% 73%","--accent-200":"290 100% 76%","--accent-900":"290 80% 25%",
"--brand-000":"309 100% 60%","--brand-100":"309 100% 73%","--brand-200":"309 100% 73%","--brand-900":"290 80% 12%",
"--pictogram-100":"300 100% 98%","--pictogram-200":"312 100% 85%","--pictogram-300":"300 17% 65%","--pictogram-400":"300 23% 25%",
"--white":"0 0% 100%","--black":"0 0% 0%","--kraft":"290 100% 76%","--book-cloth":"280 63% 63%","--manilla":"300 100% 77%",
"--clay":"309 100% 73%","--claude-accent-clay":"#eb87ff","--claude-foreground-color":"#fff5ff","--claude-background-color":"#190a1e","--claude-secondary-color":"#b496b4",
"--claude-border":"#b496b420","--claude-border-300":"#b496b430","--claude-border-300-more":"#b496b460",
"--claude-text-100":"#fff5ff","--claude-text-200":"#ffb4f0","--claude-text-400":"#b496b4","--claude-text-500":"#8c6e8c","--claude-description-text":"#ff8ce6"
},
"nord":{
"--bg-000":"220 16% 22%","--bg-100":"222 16% 18%","--bg-200":"220 17% 14%","--bg-300":"220 16% 12%","--bg-400":"220 16% 8%","--bg-500":"220 16% 6%",
"--text-000":"218 27% 94%","--text-100":"218 27% 94%","--text-200":"219 28% 88%","--text-300":"219 28% 88%","--text-400":"220 10% 55%","--text-500":"220 10% 55%",
"--accent-brand":"179 25% 65%","--accent-main-000":"193 43% 67%","--accent-main-100":"179 25% 65%","--accent-main-200":"210 34% 63%","--accent-main-900":"213 32% 30%",
"--accent-secondary-000":"210 34% 63%","--accent-secondary-100":"213 32% 52%","--accent-secondary-200":"213 32% 45%","--accent-secondary-900":"213 32% 22%",
"--accent-pro-000":"193 43% 67%","--accent-pro-100":"193 43% 52%","--accent-pro-200":"193 43% 40%","--accent-pro-900":"193 43% 20%",
"--border-100":"220 16% 28%","--border-200":"220 16% 28%","--border-300":"220 16% 32%","--border-400":"220 16% 36%",
"--danger-000":"354 42% 56%","--danger-100":"354 43% 50%","--danger-200":"354 43% 42%","--danger-900":"354 43% 20%",
"--warning-000":"40 71% 73%","--warning-100":"14 51% 63%","--warning-200":"14 50% 50%","--warning-900":"14 50% 25%",
"--success-000":"92 28% 65%","--success-100":"92 28% 55%","--success-200":"92 28% 42%","--success-900":"92 28% 20%",
"--oncolor-100":"0 0% 100%","--oncolor-200":"218 27% 94%","--oncolor-300":"219 28% 88%",
"--accent-000":"193 43% 72%","--accent-100":"193 43% 67%","--accent-200":"210 34% 63%","--accent-900":"213 32% 20%",
"--brand-000":"179 25% 55%","--brand-100":"179 25% 65%","--brand-200":"179 25% 65%","--brand-900":"220 16% 8%",
"--pictogram-100":"218 27% 94%","--pictogram-200":"219 28% 88%","--pictogram-300":"220 10% 55%","--pictogram-400":"220 16% 32%",
"--white":"0 0% 100%","--black":"0 0% 0%","--kraft":"14 51% 63%","--book-cloth":"179 25% 55%","--manilla":"40 71% 73%",
"--clay":"179 25% 65%","--claude-accent-clay":"#8FBCBB","--claude-foreground-color":"#D8DEE9","--claude-background-color":"#2E3440","--claude-secondary-color":"#8E95A4",
"--claude-border":"#4C566A30","--claude-border-300":"#4C566A40","--claude-border-300-more":"#4C566A80",
"--claude-text-100":"#ECEFF4","--claude-text-200":"#D8DEE9","--claude-text-400":"#8E95A4","--claude-text-500":"#8E95A4","--claude-description-text":"#B9BFCB"
},
"catppuccin-mocha":{
"--bg-000":"240 21% 15%","--bg-100":"240 21% 12%","--bg-200":"240 23% 9%","--bg-300":"237 16% 23%","--bg-400":"234 13% 31%","--bg-500":"232 12% 39%",
"--text-000":"226 64% 88%","--text-100":"226 64% 88%","--text-200":"227 35% 80%","--text-300":"227 35% 80%","--text-400":"228 24% 72%","--text-500":"228 24% 72%",
"--accent-brand":"267 84% 81%","--accent-main-000":"267 84% 81%","--accent-main-100":"316 72% 86%","--accent-main-200":"232 97% 85%","--accent-main-900":"267 84% 40%",
"--accent-secondary-000":"217 92% 76%","--accent-secondary-100":"198 76% 69%","--accent-secondary-200":"189 71% 73%","--accent-secondary-900":"217 92% 35%",
"--accent-pro-000":"232 97% 85%","--accent-pro-100":"217 92% 65%","--accent-pro-200":"217 92% 50%","--accent-pro-900":"217 92% 25%",
"--border-100":"234 13% 31%","--border-200":"234 13% 31%","--border-300":"232 12% 39%","--border-400":"228 17% 64%",
"--danger-000":"343 81% 75%","--danger-100":"350 65% 78%","--danger-200":"343 81% 60%","--danger-900":"343 81% 30%",
"--warning-000":"41 86% 83%","--warning-100":"23 92% 76%","--warning-200":"23 92% 60%","--warning-900":"23 92% 30%",
"--success-000":"115 54% 76%","--success-100":"170 57% 73%","--success-200":"115 54% 55%","--success-900":"115 54% 28%",
"--oncolor-100":"0 0% 100%","--oncolor-200":"226 64% 93%","--oncolor-300":"226 64% 88%",
"--accent-000":"267 84% 85%","--accent-100":"267 84% 81%","--accent-200":"232 97% 85%","--accent-900":"267 84% 30%",
"--brand-000":"267 84% 70%","--brand-100":"267 84% 81%","--brand-200":"267 84% 81%","--brand-900":"240 21% 8%",
"--pictogram-100":"226 64% 88%","--pictogram-200":"227 35% 80%","--pictogram-300":"228 24% 72%","--pictogram-400":"237 16% 23%",
"--white":"0 0% 100%","--black":"0 0% 0%","--kraft":"23 92% 76%","--book-cloth":"267 84% 70%","--manilla":"41 86% 83%",
"--clay":"267 84% 81%","--claude-accent-clay":"#cba6f7","--claude-foreground-color":"#cdd6f4","--claude-background-color":"#1e1e2e","--claude-secondary-color":"#a6adc8",
"--claude-border":"#45475a40","--claude-border-300":"#45475a40","--claude-border-300-more":"#45475a94",
"--claude-text-100":"#cdd6f4","--claude-text-200":"#bac2de","--claude-text-400":"#a6adc8","--claude-text-500":"#9399b2","--claude-description-text":"#bac2de"
},
"catppuccin-frappe":{
"--bg-000":"229 19% 23%","--bg-100":"231 19% 20%","--bg-200":"229 20% 17%","--bg-300":"230 16% 30%","--bg-400":"227 15% 37%","--bg-500":"228 13% 44%",
"--text-000":"227 70% 87%","--text-100":"227 70% 87%","--text-200":"227 44% 80%","--text-300":"227 44% 80%","--text-400":"228 30% 73%","--text-500":"228 30% 73%",
"--accent-brand":"277 59% 76%","--accent-main-000":"277 59% 76%","--accent-main-100":"316 73% 84%","--accent-main-200":"239 66% 84%","--accent-main-900":"277 59% 38%",
"--accent-secondary-000":"222 74% 74%","--accent-secondary-100":"199 55% 69%","--accent-secondary-200":"189 48% 73%","--accent-secondary-900":"222 74% 35%",
"--accent-pro-000":"239 66% 84%","--accent-pro-100":"222 74% 62%","--accent-pro-200":"222 74% 48%","--accent-pro-900":"222 74% 25%",
"--border-100":"227 15% 37%","--border-200":"227 15% 37%","--border-300":"228 13% 44%","--border-400":"228 22% 66%",
"--danger-000":"359 68% 71%","--danger-100":"358 66% 76%","--danger-200":"359 68% 56%","--danger-900":"359 68% 30%",
"--warning-000":"40 62% 73%","--warning-100":"20 79% 70%","--warning-200":"20 79% 55%","--warning-900":"20 79% 28%",
"--success-000":"96 44% 68%","--success-100":"172 39% 65%","--success-200":"96 44% 48%","--success-900":"96 44% 25%",
"--oncolor-100":"0 0% 100%","--oncolor-200":"227 70% 92%","--oncolor-300":"227 70% 87%",
"--accent-000":"277 59% 80%","--accent-100":"277 59% 76%","--accent-200":"239 66% 84%","--accent-900":"277 59% 30%",
"--brand-000":"277 59% 65%","--brand-100":"277 59% 76%","--brand-200":"277 59% 76%","--brand-900":"229 20% 8%",
"--pictogram-100":"227 70% 87%","--pictogram-200":"227 44% 80%","--pictogram-300":"228 30% 73%","--pictogram-400":"227 15% 37%",
"--white":"0 0% 100%","--black":"0 0% 0%","--kraft":"20 79% 70%","--book-cloth":"277 59% 65%","--manilla":"40 62% 73%",
"--clay":"277 59% 76%","--claude-accent-clay":"#ca9ee6","--claude-foreground-color":"#c6d0f5","--claude-background-color":"#303446","--claude-secondary-color":"#a5adce",
"--claude-border":"#51576d40","--claude-border-300":"#51576d40","--claude-border-300-more":"#51576d94",
"--claude-text-100":"#c6d0f5","--claude-text-200":"#b5bfe2","--claude-text-400":"#a5adce","--claude-text-500":"#949cbb","--claude-description-text":"#b5bfe2"
},
"catppuccin-latte":{
"--bg-000":"220 23% 95%","--bg-100":"220 22% 92%","--bg-200":"220 21% 89%","--bg-300":"223 16% 83%","--bg-400":"225 14% 77%","--bg-500":"227 12% 71%",
"--text-000":"234 16% 35%","--text-100":"234 16% 35%","--text-200":"233 13% 41%","--text-300":"233 13% 41%","--text-400":"233 10% 47%","--text-500":"233 10% 47%",
"--accent-brand":"266 85% 58%","--accent-main-000":"266 85% 58%","--accent-main-100":"316 73% 69%","--accent-main-200":"231 97% 72%","--accent-main-900":"266 85% 30%",
"--accent-secondary-000":"220 92% 54%","--accent-secondary-100":"189 70% 42%","--accent-secondary-200":"197 97% 46%","--accent-secondary-900":"220 92% 28%",
"--accent-pro-000":"231 97% 72%","--accent-pro-100":"220 92% 48%","--accent-pro-200":"220 92% 38%","--accent-pro-900":"220 92% 20%",
"--border-100":"225 14% 77%","--border-200":"225 14% 77%","--border-300":"227 12% 71%","--border-400":"228 11% 65%",
"--danger-000":"347 87% 44%","--danger-100":"355 76% 59%","--danger-200":"347 87% 38%","--danger-900":"347 87% 90%",
"--warning-000":"35 77% 49%","--warning-100":"22 99% 52%","--warning-200":"35 77% 42%","--warning-900":"35 77% 88%",
"--success-000":"109 58% 40%","--success-100":"183 74% 35%","--success-200":"109 58% 32%","--success-900":"109 58% 85%",
"--oncolor-100":"0 0% 100%","--oncolor-200":"220 23% 96%","--oncolor-300":"220 22% 92%",
"--accent-000":"266 85% 65%","--accent-100":"266 85% 58%","--accent-200":"231 97% 72%","--accent-900":"266 85% 20%",
"--brand-000":"266 85% 50%","--brand-100":"266 85% 58%","--brand-200":"266 85% 58%","--brand-900":"220 23% 8%",
"--pictogram-100":"234 16% 35%","--pictogram-200":"233 13% 41%","--pictogram-300":"233 10% 47%","--pictogram-400":"225 14% 77%",
"--white":"0 0% 100%","--black":"0 0% 0%","--kraft":"22 99% 52%","--book-cloth":"266 85% 50%","--manilla":"35 77% 49%",
"--clay":"266 85% 58%","--claude-accent-clay":"#8839ef","--claude-foreground-color":"#4c4f69","--claude-background-color":"#eff1f5","--claude-secondary-color":"#6c6f85",
"--claude-border":"#bcc0cc40","--claude-border-300":"#bcc0cc40","--claude-border-300-more":"#bcc0cc94",
"--claude-text-100":"#4c4f69","--claude-text-200":"#5c5f77","--claude-text-400":"#6c6f85","--claude-text-500":"#7c7f93","--claude-description-text":"#5c5f77"
},
"catppuccin-macchiato":{
"--bg-000":"232 23% 18%","--bg-100":"233 23% 15%","--bg-200":"236 23% 12%","--bg-300":"230 19% 26%","--bg-400":"231 16% 34%","--bg-500":"230 14% 41%",
"--text-000":"227 68% 88%","--text-100":"227 68% 88%","--text-200":"228 39% 80%","--text-300":"228 39% 80%","--text-400":"227 27% 72%","--text-500":"227 27% 72%",
"--accent-brand":"267 83% 80%","--accent-main-000":"267 83% 80%","--accent-main-100":"316 74% 85%","--accent-main-200":"234 82% 85%","--accent-main-900":"267 83% 40%",
"--accent-secondary-000":"220 83% 75%","--accent-secondary-100":"199 66% 69%","--accent-secondary-200":"189 59% 73%","--accent-secondary-900":"220 83% 35%",
"--accent-pro-000":"234 82% 85%","--accent-pro-100":"220 83% 65%","--accent-pro-200":"220 83% 50%","--accent-pro-900":"220 83% 25%",
"--border-100":"231 16% 34%","--border-200":"231 16% 34%","--border-300":"230 14% 41%","--border-400":"228 20% 65%",
"--danger-000":"351 74% 73%","--danger-100":"355 71% 77%","--danger-200":"351 74% 58%","--danger-900":"351 74% 30%",
"--warning-000":"40 70% 78%","--warning-100":"21 86% 73%","--warning-200":"21 86% 58%","--warning-900":"21 86% 30%",
"--success-000":"105 48% 72%","--success-100":"171 47% 69%","--success-200":"105 48% 52%","--success-900":"105 48% 28%",
"--oncolor-100":"0 0% 100%","--oncolor-200":"227 68% 92%","--oncolor-300":"227 68% 88%",
"--accent-000":"267 83% 85%","--accent-100":"267 83% 80%","--accent-200":"234 82% 85%","--accent-900":"267 83% 30%",
"--brand-000":"267 83% 68%","--brand-100":"267 83% 80%","--brand-200":"267 83% 80%","--brand-900":"236 23% 8%",
"--pictogram-100":"227 68% 88%","--pictogram-200":"228 39% 80%","--pictogram-300":"227 27% 72%","--pictogram-400":"231 16% 34%",
"--white":"0 0% 100%","--black":"0 0% 0%","--kraft":"21 86% 73%","--book-cloth":"267 83% 68%","--manilla":"40 70% 78%",
"--clay":"267 83% 80%","--claude-accent-clay":"#c6a0f6","--claude-foreground-color":"#cad3f5","--claude-background-color":"#24273a","--claude-secondary-color":"#a5adcb",
"--claude-border":"#494d6440","--claude-border-300":"#494d6440","--claude-border-300-more":"#494d6494",
"--claude-text-100":"#cad3f5","--claude-text-200":"#b8c0e0","--claude-text-400":"#a5adcb","--claude-text-500":"#939ab7","--claude-description-text":"#b8c0e0"
}
};
var __cdb_css="";
var __cdb_cfgPath=_path.join(_app.getPath("userData"),"claude-desktop-bin.json");
try{
console.log("[CustomThemes] Reading config: "+__cdb_cfgPath);
var __cdb_cfg=JSON.parse(_fs.readFileSync(__cdb_cfgPath,"utf8"));
var __cdb_name=__cdb_cfg.activeTheme;
if(!__cdb_name){console.log("[CustomThemes] No activeTheme set, skipping");return}
console.log("[CustomThemes] Active theme: "+__cdb_name);
var __cdb_src=(__cdb_cfg.themes&&__cdb_cfg.themes[__cdb_name])?"custom":"builtin";
var __cdb_vars=(__cdb_cfg.themes&&__cdb_cfg.themes[__cdb_name])
||__cdb_builtins[__cdb_name];
if(!__cdb_vars){console.log("[CustomThemes] Theme '"+__cdb_name+"' not found in custom themes or builtins");return}
var __cdb_rules=[];
for(var k in __cdb_vars){
if(k.indexOf("--")===0)__cdb_rules.push(k+":"+__cdb_vars[k]+" !important");
}
__cdb_rules.push("--always-black:0 0% 0% !important");
__cdb_rules.push("--always-white:0 0% 100% !important");
if(__cdb_rules.length){
__cdb_css=":root,.dark,.darkTheme,[data-theme],html{"+__cdb_rules.join(";")+"}";
__cdb_css+=""
+"html,body{color:var(--claude-foreground-color)!important}"
+"#root,[id=root]{background:hsl(var(--bg-000))!important}"
+".bg-white{background-color:hsl(var(--bg-000))!important}"
+".text-black{color:hsl(var(--text-000))!important}"
+".container{background:linear-gradient(to bottom,hsl(var(--bg-100)),hsl(var(--bg-000)))!important}"
+".container:before{border-color:hsl(var(--border-300)/0.3)!important}"
+".input-box textarea{color:var(--claude-foreground-color)!important}"
+".input-box textarea::placeholder{color:var(--claude-text-500)!important}"
+".secondary{color:var(--claude-secondary-color)!important}"
+".prose{--tw-prose-body:hsl(var(--text-200))!important;--tw-prose-headings:hsl(var(--text-000))!important;--tw-prose-lead:hsl(var(--text-300))!important;--tw-prose-links:hsl(var(--accent-main-100))!important;--tw-prose-bold:hsl(var(--text-000))!important;--tw-prose-counters:hsl(var(--text-400))!important;--tw-prose-bullets:hsl(var(--text-400))!important;--tw-prose-hr:hsl(var(--border-200))!important;--tw-prose-quotes:hsl(var(--text-200))!important;--tw-prose-quote-borders:hsl(var(--border-200))!important;--tw-prose-captions:hsl(var(--text-400))!important;--tw-prose-kbd:hsl(var(--text-000))!important;--tw-prose-code:hsl(var(--text-000))!important;--tw-prose-pre-code:hsl(var(--text-100))!important;--tw-prose-pre-bg:hsl(var(--bg-300))!important;--tw-prose-th-borders:hsl(var(--border-300))!important;--tw-prose-td-borders:hsl(var(--border-200))!important;--tw-prose-invert-body:hsl(var(--text-200))!important;--tw-prose-invert-headings:hsl(var(--text-000))!important;--tw-prose-invert-lead:hsl(var(--text-300))!important;--tw-prose-invert-links:hsl(var(--accent-main-100))!important;--tw-prose-invert-bold:hsl(var(--text-000))!important;--tw-prose-invert-counters:hsl(var(--text-400))!important;--tw-prose-invert-bullets:hsl(var(--text-400))!important;--tw-prose-invert-hr:hsl(var(--border-200))!important;--tw-prose-invert-quotes:hsl(var(--text-200))!important;--tw-prose-invert-quote-borders:hsl(var(--border-200))!important;--tw-prose-invert-captions:hsl(var(--text-400))!important;--tw-prose-invert-kbd:hsl(var(--text-000))!important;--tw-prose-invert-code:hsl(var(--text-000))!important;--tw-prose-invert-pre-code:hsl(var(--text-100))!important;--tw-prose-invert-pre-bg:hsl(var(--bg-300))!important;--tw-prose-invert-th-borders:hsl(var(--border-300))!important;--tw-prose-invert-td-borders:hsl(var(--border-200))!important}"
+"input:not([type=checkbox]):not([type=radio]):not([type=range]):not([type=color]),textarea,[contenteditable=true],.ProseMirror{background:transparent!important;color:hsl(var(--text-000))!important;border-color:hsl(var(--border-200))!important}"
+"::placeholder{color:hsl(var(--text-400))!important}"
+"[role=dialog],[role=menu],[role=listbox],[role=tooltip]{background:hsl(var(--bg-100))!important;color:hsl(var(--text-000))!important;border-color:hsl(var(--border-200))!important}"
+"hr{border-color:hsl(var(--border-200))!important}"
+"*{scrollbar-color:hsl(var(--border-300)/0.5) transparent}"
+"::selection{background:hsl(var(--accent-main-100)/0.3)!important}"
+"[type=checkbox]:checked{background-color:hsl(var(--accent-main-100))!important;border-color:hsl(var(--accent-main-100))!important}"
+"svg{color:inherit}"
+".nc-drag{color:hsl(var(--text-000))!important}";
}
console.log("[CustomThemes] Loaded "+__cdb_src+" theme '"+__cdb_name+"' with "+__cdb_rules.length+" CSS vars + element overrides");
}catch(e){
if(e.code==="ENOENT"){console.log("[CustomThemes] No config file found at "+__cdb_cfgPath+", skipping")}
else{console.log("[CustomThemes] Error reading config: "+e.message)}
}
if(!__cdb_css)return;
_app.on("web-contents-created",function(_ev,wc){
wc.on("dom-ready",function(){
try{
var url=wc.getURL()||"";
if(url.indexOf("devtools://")===0)return;
wc.insertCSS(__cdb_css);
console.log("[CustomThemes] Injected CSS into "+url);
}catch(e){console.log("[CustomThemes] insertCSS error: "+e.message)}
});
});
})();"""


def patch_custom_themes(filepath):
    """Inject custom CSS theme support for Linux."""

    print("=== Patch: add_feature_custom_themes ===")
    print(f"  Target: {filepath}")

    if not os.path.exists(filepath):
        print(f"  [FAIL] File not found: {filepath}")
        return False

    with open(filepath, "rb") as f:
        content = f.read()

    original_content = content

    # Check if already applied
    marker = b"__cdb_builtins"
    if marker in content:
        print("  [INFO] Custom theme injection already applied")
        print("  [PASS] No changes needed (already patched)")
        return True

    # Inject right after "use strict"; at the top of the file
    strict_prefix = b'"use strict";'
    if content.startswith(strict_prefix):
        content = strict_prefix + THEME_INJECTION_JS + content[len(strict_prefix) :]
        print('  [OK] Theme injection IIFE inserted after "use strict"')
    else:
        content = THEME_INJECTION_JS + content
        print("  [OK] Theme injection IIFE prepended")

    if content != original_content:
        with open(filepath, "wb") as f:
            f.write(content)
        print("  [PASS] Custom theme support added")
        return True
    else:
        print("  [WARN] No changes made")
        return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path_to_index.js>")
        sys.exit(1)

    success = patch_custom_themes(sys.argv[1])
    sys.exit(0 if success else 1)
