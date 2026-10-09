param(
    [string] $PackDirectory,
    [string] $PulseGeneratedDirectory
)

$ErrorActionPreference = 'Stop'
$protocolRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$verificationMutex = [System.Threading.Mutex]::new($false, 'Local\DCL_It2_HeavyVerification')
$acquired = $false
$previousNodeOptions = $env:NODE_OPTIONS
try {
    try { $acquired = $verificationMutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) { throw 'Heavy verification mutex occupied; retry after it is released.' }
    if ((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory -lt 5242880) {
        throw 'At least 5 GB free RAM is required.'
    }
    $env:NODE_OPTIONS = '--max-old-space-size=2048'
    Push-Location $protocolRoot
    try {
        $protocPath = Join-Path $protocolRoot 'node_modules/@protobuf-ts/protoc/installed/protoc-22.2-win64/bin/protoc.exe'
        $pluginPath = Join-Path $protocolRoot 'node_modules/.bin/protoc-gen-dcl_ts_proto.cmd'
        if (-not (Test-Path -LiteralPath $protocPath)) { throw 'Install the locked protocol dependencies first.' }
        # Match scripts/test.sh: remove only the three ignored, repo-local generated directories.
        foreach ($outputName in @('out-ts', 'out-js', 'out-cs')) {
            $outputPath = [System.IO.Path]::GetFullPath((Join-Path $protocolRoot $outputName))
            if ([System.IO.Path]::GetDirectoryName($outputPath) -ne $protocolRoot) {
                throw 'Generated output directory escaped the protocol repository.'
            }
            if (Test-Path -LiteralPath $outputPath) {
                $outputItem = Get-Item -LiteralPath $outputPath -Force
                if ($outputItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                    throw "Refusing generated output junction or symlink: $outputPath"
                }
                Remove-Item -LiteralPath $outputPath -Recurse -Force
            }
            New-Item -ItemType Directory -Path $outputPath | Out-Null
        }
        foreach ($protoFile in Get-ChildItem -LiteralPath public -Filter '*.proto') {
            & $protocPath "--plugin=protoc-gen-dcl_ts_proto=$pluginPath" `
                '--dcl_ts_proto_opt=esModuleInterop=true,returnObservable=false,outputServices=generic-definitions,fileSuffix=.gen,oneof=unions' `
                --dcl_ts_proto_out=out-ts --csharp_out=out-cs -I=proto -I=public "public/$($protoFile.Name)"
            if ($LASTEXITCODE -ne 0) { throw "protoc failed: $($protoFile.Name)" }
        }
        & ./node_modules/.bin/tsc.cmd -p tsconfig.json
        if ($LASTEXITCODE -ne 0) { throw 'Generated TypeScript compilation failed.' }
        if ($PulseGeneratedDirectory) {
            # Only this schema is emitted into the consumer; other C# bindings remain untouched.
            & $protocPath -I=proto "--csharp_out=$PulseGeneratedDirectory" proto/decentraland/pulse/pulse_clusters.proto
            if ($LASTEXITCODE -ne 0) { throw 'Scoped PulseClusters.cs generation failed.' }
        }
        if ($PackDirectory) {
            New-Item -ItemType Directory -Path $PackDirectory -Force | Out-Null
            $packResult = npm pack --pack-destination $PackDirectory --json | ConvertFrom-Json
            if ($LASTEXITCODE -ne 0) { throw 'Local protocol packaging failed.' }
            $packResult | Select-Object id, size, unpackedSize, shasum, integrity, filename
            Get-FileHash -LiteralPath (Join-Path $PackDirectory 'dcl-protocol-1.0.0.tgz') -Algorithm SHA256
        }
    } finally { Pop-Location }
} finally {
    $env:NODE_OPTIONS = $previousNodeOptions
    if ($acquired) { $verificationMutex.ReleaseMutex() }
    $verificationMutex.Dispose()
}
