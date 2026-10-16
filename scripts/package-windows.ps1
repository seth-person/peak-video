$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$stage = Join-Path $root 'dist/windows-stage'
$cache = Join-Path $root 'vendor'
New-Item -ItemType Directory -Force $stage, $cache, "$stage/Tools", "$stage/Licenses" | Out-Null
$lock = Get-Content "$PSScriptRoot/dependencies.json" -Raw | ConvertFrom-Json
function Fetch($name) {
    $item = $lock.$name
    $path = Join-Path $cache $name
    if (!(Test-Path $path)) { Invoke-WebRequest $item.url -OutFile $path }
    if ((Get-FileHash $path -Algorithm SHA256).Hash.ToLower() -ne $item.sha256) { throw "Checksum mismatch: $name" }
    return $path
}
dotnet publish "$root/windows/Peak/Peak.csproj" -c Release -r win-x64 -o $stage
if ($LASTEXITCODE -ne 0) { throw 'Application build failed' }
Copy-Item (Fetch 'yt-dlp.exe') "$stage/Tools/yt-dlp.exe"
Expand-Archive (Fetch 'deno-windows.zip') "$cache/deno-windows" -Force
Copy-Item "$cache/deno-windows/deno.exe" "$stage/Tools/deno.exe"
Expand-Archive (Fetch 'ffmpeg-windows.zip') "$cache/ffmpeg-windows" -Force
$ff = Get-ChildItem "$cache/ffmpeg-windows" -Directory | Select-Object -First 1
Copy-Item "$($ff.FullName)/bin/ffmpeg.exe", "$($ff.FullName)/bin/ffprobe.exe" "$stage/Tools/"
Copy-Item "$($ff.FullName)/LICENSE" "$stage/Licenses/FFmpeg-LICENSE.txt"
Copy-Item "$root/THIRD_PARTY.md", "$root/LICENSE" $stage
$notices = @{
  'yt-dlp-LICENSE.txt' = 'https://raw.githubusercontent.com/yt-dlp/yt-dlp/2026.08.19/LICENSE'
  'yt-dlp-THIRD_PARTY_LICENSES.txt' = 'https://raw.githubusercontent.com/yt-dlp/yt-dlp/2026.08.19/THIRD_PARTY_LICENSES.txt'
  'Deno-LICENSE.md' = 'https://raw.githubusercontent.com/denoland/deno/v2.9.7/LICENSE.md'
  'dotnet-LICENSE.txt' = 'https://raw.githubusercontent.com/dotnet/runtime/v10.0.10/LICENSE.TXT'
  'dotnet-THIRD-PARTY-NOTICES.txt' = 'https://raw.githubusercontent.com/dotnet/runtime/v10.0.10/THIRD-PARTY-NOTICES.TXT'
}
foreach ($name in $notices.Keys) { Invoke-WebRequest $notices[$name] -OutFile "$stage/Licenses/$name" }
$manifest = @{ version = '1.1.0'; architecture = 'win-x64'; dotnet = (dotnet --version); dependencies = @{} }
foreach ($name in @('yt-dlp.exe', 'deno-windows.zip', 'ffmpeg-windows.zip')) { $manifest.dependencies[$name] = $lock.$name }
$manifest | ConvertTo-Json -Depth 6 | Set-Content "$stage/dependency-manifest.json"
$p = Start-Process "$stage/Peak.exe" '--self-test' -Wait -PassThru
if ($p.ExitCode -ne 0) { Get-Content "$stage/self-test-error.txt"; throw 'Windows self-test failed' }
Get-Content "$stage/self-test-passed.txt"
Remove-Item "$stage/self-test-passed.txt"
$makensis = (Get-Command makensis.exe -ErrorAction SilentlyContinue).Source
if (!$makensis) { $makensis = "${env:ProgramFiles(x86)}/NSIS/makensis.exe" }
& $makensis "/DSTAGE=$stage" "/DOUTPUT=$root/dist/Peak-1.1.0-windows-x64.exe" "$PSScriptRoot/windows-installer.nsi"
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed' }
Copy-Item "$stage/dependency-manifest.json" "$root/dist/dependency-manifest-windows-x64.json"
$artifact = Get-Item "$root/dist/Peak-1.1.0-windows-x64.exe"
"$((Get-FileHash $artifact -Algorithm SHA256).Hash.ToLower())  $($artifact.Name)" | Set-Content "$root/dist/SHA256SUMS-windows-x64.txt"
