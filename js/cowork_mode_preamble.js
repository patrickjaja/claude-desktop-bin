(function(){
  if(process.platform!=="linux")return;
  var _fs=require("fs"),_path=require("path");
  var _rundir=process.env.XDG_RUNTIME_DIR||"/tmp";
  var envBackend=process.env.COWORK_VM_BACKEND;
  var autoMode="native";
  if(!envBackend){
    try{_fs.accessSync(_path.join(_rundir,"cowork-sandbox-service.sock"));autoMode="sandbox";}catch(e){
      try{_fs.accessSync(_path.join(_rundir,"cowork-kvm-service.sock"));autoMode="kvm";}catch(e2){}
    }
  }
  var _mode=envBackend||autoMode;
  globalThis.__coworkKvmMode=_mode==="kvm";
  globalThis.__coworkSandboxMode=_mode==="sandbox";
  var _sockName=globalThis.__coworkKvmMode?"cowork-kvm-service.sock":globalThis.__coworkSandboxMode?"cowork-sandbox-service.sock":"cowork-vm-service.sock";
  var _sockPath=_path.join(_rundir,_sockName);
  globalThis.__coworkSocketPath=_sockPath;
  globalThis.__coworkServiceAvailable=false;
  try{_fs.accessSync(_sockPath);globalThis.__coworkServiceAvailable=true;}catch(e){}
  console.log("[claude-cowork] mode="+_mode+(envBackend?" (COWORK_VM_BACKEND set)":autoMode==="sandbox"?" (auto: sandbox socket present)":autoMode==="kvm"?" (auto: kvm socket present)":" (auto: native default)")+", service="+(globalThis.__coworkServiceAvailable?"available":"not found"));
  if(!globalThis.__coworkServiceAvailable){
    console.log("[claude-cowork] Cowork service not running. Chat and Code tabs work normally. To enable Cowork: install claude-cowork-service (https://github.com/patrickjaja/claude-cowork-service), start the service, then restart Claude Desktop or wait ~60s for auto-detection.");
  }
})();
