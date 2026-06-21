#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_BIN="$ROOT_DIR/patches/fix_cowork_download_status_linux"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ! -x "$PATCH_BIN" ]]; then
    echo "Missing compiled patch: $PATCH_BIN" >&2
    exit 1
fi

ORIGINAL_STATUS_EXPR='dl()?State.Downloading:ready()?State.Ready:State.NotDownloaded'
ORIGINAL_STATUS="getDownloadStatus(){return ${ORIGINAL_STATUS_EXPR}}"
ORIGINAL_DOWNLOAD='async download(){try{return await provision(),{success:ready()}}catch(err){return{success:false,error:String(err)}}}'
ORIGINAL_PROVISIONING='setYukonSilverConfig(cfg){save(cfg),cfg.autoDownloadInBackground&&!busy&&(busy=!0,startDownload())}'
STATUS_GUARD='getDownloadStatus(){return process.platform==="linux"&&!globalThis.__coworkKvmMode?State.Ready:'
DOWNLOAD_GUARD='async download(){if(process.platform==="linux"&&!globalThis.__coworkKvmMode)return{success:!0};'
PROVISIONING_GUARD='setYukonSilverConfig(cfg){save(cfg);if(process.platform==="linux"&&!globalThis.__coworkKvmMode)return;cfg.autoDownloadInBackground&&'

assert_contains() {
    local file=$1
    local expected=$2
    if ! grep -Fq "$expected" "$file"; then
        echo "Expected patched output not found: $expected" >&2
        exit 1
    fi
}

cat >"$TMP_DIR/fresh.js" <<EOF
const assert=require("node:assert/strict");
const State={Downloading:"downloading",Ready:"ready",NotDownloaded:"not-downloaded"};
let provisionCalls=0,backgroundCalls=0,saveCalls=0,busy=false;
const dl=()=>false,ready=()=>false;
const provision=async()=>{provisionCalls++;return true};
const save=()=>{saveCalls++};
const startDownload=()=>{backgroundCalls++};
const service={${ORIGINAL_DOWNLOAD},${ORIGINAL_STATUS},${ORIGINAL_PROVISIONING}};
async function verifyRuntimeGuards(){
    globalThis.__coworkKvmMode=false;
    assert.deepEqual(await service.download(),{success:true});
    service.setYukonSilverConfig({autoDownloadInBackground:true});
    assert.deepEqual({provisionCalls,backgroundCalls,saveCalls},{provisionCalls:0,backgroundCalls:0,saveCalls:1});

    provisionCalls=0;backgroundCalls=0;saveCalls=0;busy=false;
    globalThis.__coworkKvmMode=true;
    await service.download();
    service.setYukonSilverConfig({autoDownloadInBackground:true});
    assert.deepEqual({provisionCalls,backgroundCalls,saveCalls},{provisionCalls:1,backgroundCalls:1,saveCalls:1});
}
verifyRuntimeGuards().catch(error=>{console.error(error);process.exitCode=1});
EOF

"$PATCH_BIN" "$TMP_DIR/fresh.js"
assert_contains "$TMP_DIR/fresh.js" "$STATUS_GUARD"
assert_contains "$TMP_DIR/fresh.js" "$DOWNLOAD_GUARD"
assert_contains "$TMP_DIR/fresh.js" "$PROVISIONING_GUARD"
assert_contains "$TMP_DIR/fresh.js" "$ORIGINAL_STATUS_EXPR"
assert_contains "$TMP_DIR/fresh.js" 'try{return await provision(),{success:ready()}}'
assert_contains "$TMP_DIR/fresh.js" 'cfg.autoDownloadInBackground&&!busy&&(busy=!0,startDownload())'
node --check "$TMP_DIR/fresh.js"
node "$TMP_DIR/fresh.js"

cp "$TMP_DIR/fresh.js" "$TMP_DIR/once.js"
"$PATCH_BIN" "$TMP_DIR/fresh.js"
cmp "$TMP_DIR/once.js" "$TMP_DIR/fresh.js"

cat >"$TMP_DIR/partial.js" <<EOF
const State={Downloading:"downloading",Ready:"ready",NotDownloaded:"not-downloaded"};
const service={${ORIGINAL_DOWNLOAD},${STATUS_GUARD}${ORIGINAL_STATUS_EXPR}},${ORIGINAL_PROVISIONING}};
EOF

"$PATCH_BIN" "$TMP_DIR/partial.js"
assert_contains "$TMP_DIR/partial.js" "$STATUS_GUARD"
assert_contains "$TMP_DIR/partial.js" "$DOWNLOAD_GUARD"
assert_contains "$TMP_DIR/partial.js" "$PROVISIONING_GUARD"
node --check "$TMP_DIR/partial.js"

echo "Linux-native Cowork VM download guard tests passed"
