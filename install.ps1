$ErrorActionPreference = 'Stop'
$version = $env:SETUP_VERSION
if ($version -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$') { throw 'version must be an exact release tag' }
$independent = $env:SETUP_EXPECTED_SHA256
if ($independent -and $independent -notmatch '^[0-9a-fA-F]{64}$') { throw 'expected-sha256 must contain 64 hexadecimal characters' }
$osName = switch ($env:RUNNER_OS) { 'Linux' { 'linux' } 'macOS' { 'darwin' } 'Windows' { 'windows' } default { throw "unsupported runner OS: $env:RUNNER_OS" } }
$arch = switch ($env:RUNNER_ARCH) { 'X64' { 'amd64' } 'ARM64' { 'arm64' } default { throw "unsupported runner architecture: $env:RUNNER_ARCH" } }
if ($osName -eq 'windows' -and $arch -eq 'arm64') { throw 'OpenVaultDB does not publish a Windows arm64 archive' }
$number = $version.Substring(1)
$extension = if ($osName -eq 'windows') { 'zip' } else { 'tar.gz' }
$archive = "ovdb_${number}_${osName}_${arch}.${extension}"
$base = "https://github.com/openvaultdb/ovdb/releases/download/$version"
$tmp = Join-Path $env:RUNNER_TEMP ("setup-ovdb-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $archivePath = Join-Path $tmp $archive
    $manifestPath = Join-Path $tmp 'checksums.txt'
    Invoke-WebRequest -Uri "$base/$archive" -OutFile $archivePath
    Invoke-WebRequest -Uri "$base/checksums.txt" -OutFile $manifestPath
    $entries = @(Get-Content $manifestPath | Where-Object { $_ -match "\s\*?$([regex]::Escape($archive))\s*$" })
    if ($entries.Count -ne 1) { throw "missing or duplicate checksum for $archive" }
    $expected = ($entries[0] -split '\s+')[0]
    if ($expected -notmatch '^[0-9a-fA-F]{64}$') { throw "invalid checksum for $archive" }
    $actual = (Get-FileHash -Algorithm SHA256 -Path $archivePath).Hash
    if ($actual -ine $expected) { throw "checksum mismatch for $archive" }
    if ($independent -and $actual -ine $independent) { throw "expected-sha256 mismatch for $archive" }
    $extract = Join-Path $tmp 'extract'
    New-Item -ItemType Directory -Path $extract | Out-Null
    if ($extension -eq 'zip') { Expand-Archive -Path $archivePath -DestinationPath $extract }
    else {
        & tar -xzf $archivePath -C $extract
        if ($LASTEXITCODE -ne 0) { throw 'archive extraction failed' }
    }
    $name = if ($osName -eq 'windows') { 'ovdb.exe' } else { 'ovdb' }
    $source = Join-Path $extract $name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'binary missing from archive' }
    $destination = Join-Path $env:RUNNER_TEMP ("ovdb-bin-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $destination | Out-Null
    Copy-Item -LiteralPath $source -Destination (Join-Path $destination $name)
    if ($osName -ne 'windows') { & chmod +x (Join-Path $destination $name); if ($LASTEXITCODE -ne 0) { throw 'chmod failed' } }
    Add-Content -Path $env:GITHUB_PATH -Value $destination
    Add-Content -Path $env:GITHUB_OUTPUT -Value "version=$version"
} finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
