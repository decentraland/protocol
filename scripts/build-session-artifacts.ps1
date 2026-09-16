$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$mutex = [Threading.Mutex]::new($false, 'Local\DCL_It2_HeavyVerification')
$acquired = $false
try {
  try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
  if (-not $acquired) { Write-Output 'Heavy verification occupied; retry later.'; exit 75 }
  $freeGiB = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB
  Write-Output "Free physical RAM: $freeGiB GiB"
  if ($freeGiB -lt 7) { throw 'Need 5 GiB reserve plus 2 GiB Node heap headroom.' }
  $env:NODE_OPTIONS = '--max-old-space-size=2048'
  function Check-Exit { if ($LASTEXITCODE -ne 0) { throw "Command failed: $LASTEXITCODE" } }
  New-Item -ItemType Directory -Force out-ts,out-js,out-session-takeover | Out-Null
  Copy-Item node_modules/.bin/buf node_modules/.bin/buf.exe -Force
  & node_modules/.bin/buf.exe lint proto/
  Check-Exit
  & node_modules/.bin/buf.exe build proto/
  Check-Exit
  & node_modules/.bin/buf.exe breaking proto/ --against 'https://github.com/decentraland/protocol.git#subdir=proto'
  Check-Exit
  foreach ($file in Get-ChildItem public/*.proto) {
    $plugin = (Resolve-Path node_modules/.bin/protoc-gen-dcl_ts_proto.cmd).Path
    & node_modules/.bin/protoc.cmd ("--plugin=protoc-gen-dcl_ts_proto=" + $plugin) --dcl_ts_proto_opt=esModuleInterop=true,returnObservable=false,outputServices=generic-definitions,fileSuffix=.gen,oneof=unions --dcl_ts_proto_out=out-ts -I=proto -I=public ("public/" + $file.Name)
    Check-Exit
  }
  & node_modules/.bin/tsc.cmd -p tsconfig.json
  Check-Exit
  & node_modules/.bin/protoc.cmd --csharp_out=out-session-takeover --csharp_opt=file_extension=.gen.cs -I=proto proto/decentraland/kernel/comms/v3/archipelago.proto
  Check-Exit
  node test/session-control.test.js
  Check-Exit
  npm run gen:test
  Check-Exit
  npm pack --pack-destination out-session-takeover
  Check-Exit
  Get-FileHash out-session-takeover/Archipelago.gen.cs,out-session-takeover/dcl-protocol-1.0.0.tgz -Algorithm SHA256
} finally {
  if ($acquired) { $mutex.ReleaseMutex() }
  $mutex.Dispose()
}
