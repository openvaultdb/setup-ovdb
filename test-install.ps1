param([switch]$Child, [string]$Mode, [string]$Fixture, [string]$Archive)
$ErrorActionPreference = 'Stop'
if ($Child) {
    function Invoke-WebRequest {
        param($Uri, $OutFile)
        $base = 'https://github.com/openvaultdb/ovdb/releases/download/v1.2.3'
        if ($Uri -eq "$base/$Archive") { Copy-Item "$Fixture/archive" $OutFile }
        elseif ($Uri -eq "$base/checksums.txt") { Copy-Item "$Fixture/checksums.txt" $OutFile }
        else { throw "unexpected URL: $Uri" }
    }
    $env:SETUP_VERSION = 'v1.2.3'
    $env:SETUP_EXPECTED_SHA256 = if ($Mode -eq 'independent') { '0' * 64 } else { '' }
    $env:GITHUB_PATH = Join-Path $Fixture 'path'
    $env:GITHUB_OUTPUT = Join-Path $Fixture 'output'
    . (Join-Path $PSScriptRoot 'install.ps1')
    exit 0
}
$tmp = Join-Path $env:RUNNER_TEMP ("setup-ovdb-test-" + [guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
try {
    $osName = switch ($env:RUNNER_OS) { 'Linux' { 'linux' } 'macOS' { 'darwin' } 'Windows' { 'windows' } }
    $arch = switch ($env:RUNNER_ARCH) { 'X64' { 'amd64' } 'ARM64' { 'arm64' } }
    $ext = if ($osName -eq 'windows') { 'zip' } else { 'tar.gz' }
    $binary = if ($osName -eq 'windows') { 'ovdb.exe' } else { 'ovdb' }
    $archive = "ovdb_1.2.3_${osName}_${arch}.$ext"
    Set-Content (Join-Path $tmp $binary) 'fixture'
    if ($ext -eq 'zip') {
        Compress-Archive -Path (Join-Path $tmp $binary) -DestinationPath (Join-Path $tmp 'archive.zip')
        Move-Item (Join-Path $tmp 'archive.zip') (Join-Path $tmp 'archive')
    } else {
        & tar -czf (Join-Path $tmp 'archive') -C $tmp $binary
        if ($LASTEXITCODE -ne 0) { throw 'fixture archive creation failed' }
    }
    $hash = (Get-FileHash -Algorithm SHA256 (Join-Path $tmp 'archive')).Hash
    Set-Content (Join-Path $tmp 'checksums.txt') "$hash  $archive"
    $log = Join-Path $tmp 'log'
    & pwsh -NoProfile -File $PSCommandPath -Child -Mode independent -Fixture $tmp -Archive $archive *> $log
    if ($LASTEXITCODE -eq 0 -or (Get-Content -Raw $log) -notmatch 'expected-sha256 mismatch') { throw 'independent digest failure not detected' }
    Set-Content (Join-Path $tmp 'checksums.txt') (('0' * 64) + "  $archive")
    & pwsh -NoProfile -File $PSCommandPath -Child -Mode manifest -Fixture $tmp -Archive $archive *> $log
    if ($LASTEXITCODE -eq 0 -or (Get-Content -Raw $log) -notmatch 'checksum mismatch') { throw 'manifest mismatch not detected' }
} finally { Remove-Item -Recurse -Force $tmp }
exit 0
