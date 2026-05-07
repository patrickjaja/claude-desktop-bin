(function(){
  if(process.platform!=="linux")return;
  var envBackend=process.env.COWORK_VM_BACKEND;
  var autoMode="native";
  if(!envBackend){
    var _fs=require("fs"),_path=require("path");
    var _rundir=process.env.XDG_RUNTIME_DIR||"/tmp";
    try{_fs.accessSync(_path.join(_rundir,"cowork-sandbox-service.sock"));autoMode="sandbox";}catch(e){
      try{_fs.accessSync(_path.join(_rundir,"cowork-kvm-service.sock"));autoMode="kvm";}catch(e2){}
    }
  }
  var _mode=envBackend||autoMode;
  globalThis.__coworkKvmMode=_mode==="kvm";
  globalThis.__coworkSandboxMode=_mode==="sandbox";
  console.log("[claude-cowork] mode="+_mode+(envBackend?" (COWORK_VM_BACKEND set)":autoMode==="sandbox"?" (auto: sandbox socket present)":autoMode==="kvm"?" (auto: kvm socket present)":" (auto: native default)"));
})();
