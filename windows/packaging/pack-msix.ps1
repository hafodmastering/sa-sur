# Builds the Microsoft Store package (MSIX) for SA-Sur.
#
# Run it on Windows. It does the four things the Store needs and nothing else:
#
#   1. publishes the app with the Store line's version stamped in (-p:Version), so the version the
#      Store shows and the version inside the binary agree - the same rule tools/store-build.sh
#      applies to the macOS store build, for the same reason (see D22);
#   2. stages the publish output in the MSIX layout with the tile assets and a manifest built from
#      store-identity.psd1;
#   3. packs it with MakeAppx, which validates the manifest against the schema;
#   4. reads the result back - unpacking it and printing the payload's version and digests - so the
#      build is verified rather than assumed.
#
# Signing is optional. A Store submission does NOT need our signature (the Store re-signs the
# package after certification), but Windows will not install an unsigned package for a local test,
# so -SelfSign creates a throwaway certificate with the identity's subject and trusts it in
# LocalMachine\TrustedPeople (elevation required).
#
# Usage:
#   .\pack-msix.ps1                          # build + verify, unsigned
#   .\pack-msix.ps1 -SelfSign -Install       # build, sign with a dev cert, install and smoke-test
#   .\pack-msix.ps1 -Version 1.1.0.0 -OutDir C:\Install\sasur-msix-2026-10-14\out
[CmdletBinding()]
param(
    [string]$Version,
    # Defaults are resolved in the body, not here: Windows PowerShell 5.1 evaluates a param()
    # default outside the script scope, where $PSScriptRoot is empty, so `-File` invocation used to
    # fail with "Cannot bind argument to parameter 'Path' because it is an empty string".
    [string]$Identity,
    [string]$OutDir,
    [string]$Configuration = 'Release',
    [string]$Screenshots,
    [switch]$SelfSign,
    [switch]$Install,
    [string]$MakeAppx
)

$ErrorActionPreference = 'Stop'
$packaging = $PSScriptRoot
if (-not $Identity) { $Identity = Join-Path $packaging 'store-identity.psd1' }
if (-not $OutDir) { $OutDir = Join-Path $packaging 'out' }
$windowsDir = Split-Path $packaging -Parent
$project = Join-Path $windowsDir 'SA-Sur.App\SaSur.App.csproj'

# This estate installs the .NET SDK by unpacking it (no MSI, no elevation) and deliberately leaves
# PATH alone, so the SDK is usually there but not on PATH. Add it for this process only.
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    foreach ($candidate in @('C:\Tools\dotnet', (Join-Path $env:ProgramFiles 'dotnet'))) {
        $exe = Join-Path $candidate 'dotnet.exe'
        if (Test-Path $exe) { $env:Path = $candidate + ';' + $env:Path; break }
    }
}
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "dotnet not found; install the .NET SDK or put it on PATH"
}
Write-Output ("dotnet  : " + (dotnet --version))

Write-Output "== identity =="
$id = Import-PowerShellDataFile -Path $Identity
if ($Version) { $id.Version = $Version }
if ($id.Version -notmatch '^\d+\.\d+\.\d+\.0$') {
    throw "Version must be four numeric parts ending in .0 (Partner Center reserves the revision field); got '$($id.Version)'"
}
$id.GetEnumerator() | Sort-Object Key | ForEach-Object { Write-Output ("  {0,-20} {1}" -f $_.Key, $_.Value) }

Write-Output "== MakeAppx =="
if (-not $MakeAppx) {
    $candidates = @()
    if (Test-Path 'C:\Tools\sdk-buildtools') {
        $candidates += Get-ChildItem 'C:\Tools\sdk-buildtools' -Recurse -Filter makeappx.exe -ErrorAction SilentlyContinue
    }
    $candidates += Get-Command makeappx.exe -ErrorAction SilentlyContinue | ForEach-Object { Get-Item $_.Source }
    if (-not $candidates) {
        throw "makeappx.exe not found. Install Microsoft.Windows.SDK.BuildTools (see windows/packaging/README.md)."
    }
    # Prefer the x64 build.
    $MakeAppx = ($candidates | Where-Object { $_.FullName -match '\\x64\\' } | Select-Object -First 1).FullName
    if (-not $MakeAppx) { $MakeAppx = $candidates[0].FullName }
}
Write-Output ("  " + $MakeAppx)

Write-Output "== publish ($Configuration, win-x64, self-contained, trimmed, version $($id.Version)) =="
$publish = Join-Path $OutDir 'publish'
$stage = Join-Path $OutDir 'stage'
foreach ($d in @($publish, $stage)) {
    if (Test-Path $d) { Remove-Item $d -Recurse -Force }
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}
$exe = Join-Path $publish 'SA-Sur.exe'
dotnet publish $project -c $Configuration -r win-x64 --self-contained true `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:Version=$($id.Version) -o $publish
if (-not (Test-Path $exe)) { throw "publish produced no SA-Sur.exe" }
$built = Get-Item $exe
Write-Output ("  exe     : {0:N0} bytes" -f $built.Length)
Write-Output ("  version : " + $built.VersionInfo.ProductVersion)

Write-Output "== staging =="
Copy-Item (Join-Path $publish '*') $stage -Recurse -Force
# Debug symbols are not part of what a user installs, and the package is the thing they download.
Get-ChildItem $stage -Filter *.pdb -Recurse -File | Remove-Item -Force
Copy-Item (Join-Path $packaging 'Assets') (Join-Path $stage 'Assets') -Recurse -Force

# The documents. A Store user never sees the GitHub release page, so the manual and the licences
# have to be inside the package: the Help menu opens the manual and shows the licence texts, and
# the same files satisfy Apache-2.0 section 4 for anyone who unpacks the MSIX.
Write-Output "== documents =="
$repo = Split-Path $windowsDir -Parent
$manual = Join-Path $repo 'docs\SA-Sur-User-Manual.pdf'
$manualSource = Join-Path $repo 'docs\MANUAL.md'
if (-not (Test-Path $manual)) {
    throw "no docs/SA-Sur-User-Manual.pdf - run tools/manual.sh (the manual is a shipped resource, and the Help menu is dead without it)"
}
$pdfTime = (Get-Item $manual).LastWriteTimeUtc
$mdTime = (Get-Item $manualSource).LastWriteTimeUtc
if ($pdfTime -lt $mdTime) {
    throw ("docs/SA-Sur-User-Manual.pdf is older than docs/MANUAL.md ({0} vs {1}) - re-render it before packaging" -f $pdfTime, $mdTime)
}
Copy-Item $manual (Join-Path $stage 'SA-Sur-Manual.pdf') -Force

$documents = @(
    @{ Source = 'LICENSE';                    Target = 'LICENSE' },
    @{ Source = 'NOTICE';                     Target = 'NOTICE' },
    @{ Source = 'EULA.md';                    Target = 'EULA.txt' },
    @{ Source = 'THIRD-PARTY-NOTICES.md';     Target = 'THIRD-PARTY-NOTICES.txt' },
    @{ Source = 'windows\SA-Sur.Ui\Assets\Fonts\OFL.txt'; Target = 'OFL.txt' }
)
foreach ($doc in $documents) {
    $from = Join-Path $repo $doc.Source
    if (-not (Test-Path $from)) { throw ("missing document: {0}" -f $doc.Source) }
    Copy-Item $from (Join-Path $stage $doc.Target) -Force
}
Write-Output ("  documents: SA-Sur-Manual.pdf ({0:N0} bytes), LICENSE, NOTICE, EULA.txt, THIRD-PARTY-NOTICES.txt, OFL.txt" -f (Get-Item $manual).Length)

# A screenshot that predates the source is a claim about a build that does not exist. Checked
# against the newest source file rather than a date typed in by hand.
if ($Screenshots) {
    Write-Output "== screenshots =="
    $newestSource = Get-ChildItem (Join-Path $windowsDir '*') -Recurse -File -Include *.cs, *.axaml, *.csproj |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    $shots = Get-ChildItem $Screenshots -Filter '*.png' -File -ErrorAction SilentlyContinue
    if (-not $shots) { throw ("no screenshots in {0} - run tools/windows-store-screenshots.sh" -f $Screenshots) }
    foreach ($shot in $shots) {
        if ($shot.LastWriteTimeUtc -lt $newestSource.LastWriteTimeUtc) {
            throw ("{0} is older than {1} - re-render the screenshots for this commit" -f $shot.Name, $newestSource.Name)
        }
        Write-Output ("  {0}  {1:N0} bytes" -f $shot.Name, $shot.Length)
    }
}
$manifest = Get-Content (Join-Path $packaging 'AppxManifest.xml') -Raw
$manifest = $manifest.Replace('__PACKAGE_NAME__', $id.PackageName).
    Replace('__PUBLISHER__', $id.Publisher).
    Replace('__PUBLISHER_DISPLAY_NAME__', $id.PublisherDisplayName).
    Replace('__VERSION__', $id.Version)
$manifestPath = Join-Path $stage 'AppxManifest.xml'
Set-Content -Path $manifestPath -Value $manifest -Encoding UTF8

# The manifest must not reference an asset that is not there; MakeAppx fails late and cryptically.
$missing = @()
foreach ($m in [regex]::Matches($manifest, 'Assets\\[A-Za-z0-9\.\-]+\.png')) {
    $p = Join-Path $stage ($m.Value -replace '\\', '/')
    if (-not (Test-Path $p)) { $missing += $m.Value }
}
if ($missing) { throw ("manifest references missing assets: " + ($missing -join ', ')) }
Write-Output ("  staged  : " + ((Get-ChildItem $stage -Recurse -File).Count) + " files")

Write-Output "== pack =="
$msix = Join-Path $OutDir ("SA-Sur_{0}_x64.msix" -f $id.Version)
if (Test-Path $msix) { Remove-Item $msix -Force }
& $MakeAppx pack /d $stage /p $msix /o
if ($LASTEXITCODE -ne 0) { throw "makeappx pack failed ($LASTEXITCODE)" }
$pack = Get-Item $msix
Write-Output ("  package : " + $pack.FullName)
Write-Output ("  size    : {0:N0} bytes" -f $pack.Length)
Write-Output ("  sha256  : " + (Get-FileHash $msix -Algorithm SHA256).Hash.ToLower())

Write-Output "== read back (unpack and inspect the payload) =="
$verify = Join-Path $OutDir 'verify'
if (Test-Path $verify) { Remove-Item $verify -Recurse -Force }
New-Item -ItemType Directory -Path $verify | Out-Null
& $MakeAppx unpack /p $msix /d $verify /o | Out-Null
if ($LASTEXITCODE -ne 0) { throw "makeappx unpack failed ($LASTEXITCODE)" }
$payloadManifest = [xml](Get-Content (Join-Path $verify 'AppxManifest.xml') -Raw)
$payloadExe = Get-Item (Join-Path $verify 'SA-Sur.exe')
Write-Output ("  identity: " + $payloadManifest.Package.Identity.Name)
Write-Output ("  version : " + $payloadManifest.Package.Identity.Version + "  (binary reports " + $payloadExe.VersionInfo.ProductVersion + ")")
Write-Output ("  exe hash: " + (Get-FileHash $payloadExe.FullName -Algorithm SHA256).Hash.ToLower())
if ($payloadExe.VersionInfo.ProductVersion -notlike ($id.Version + '*')) {
    throw "the packaged binary does not report the Store version: the stamp did not reach the build"
}
Write-Output "  version stamp reached the binary: OK"

if ($SelfSign) {
    Write-Output "== self-signed test certificate =="
    $subject = $id.Publisher
    $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq $subject -and $_.HasPrivateKey } | Select-Object -First 1
    if (-not $cert) {
        $cert = New-SelfSignedCertificate -Type Custom -Subject $subject `
            -KeyUsage DigitalSignature -FriendlyName 'SA-Sur MSIX test signing' `
            -CertStoreLocation 'Cert:\LocalMachine\My' `
            -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
        Write-Output ("  created : " + $cert.Thumbprint)
    } else {
        Write-Output ("  reused  : " + $cert.Thumbprint)
    }
    $trusted = Get-ChildItem Cert:\LocalMachine\TrustedPeople | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
    if (-not $trusted) {
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('TrustedPeople', 'LocalMachine')
        $store.Open('ReadWrite'); $store.Add($cert); $store.Close()
        Write-Output "  trusted : added to LocalMachine\TrustedPeople"
    } else {
        Write-Output "  trusted : already in LocalMachine\TrustedPeople"
    }
    $signtool = (Get-ChildItem (Split-Path $MakeAppx -Parent) -Filter signtool.exe | Select-Object -First 1).FullName
    & $signtool sign /fd SHA256 /sha1 $cert.Thumbprint /sm $msix
    if ($LASTEXITCODE -ne 0) { throw "signtool sign failed ($LASTEXITCODE)" }
    Write-Output "  verify  :"
    & $signtool verify /pa /v $msix | Select-String -Pattern 'Successfully verified|Issued to|SHA1 hash of file' | ForEach-Object { Write-Output ("    " + $_.Line.Trim()) }
    Write-Output ("  signed  : " + $msix)
}

if ($Install) {
    Write-Output "== install =="
    $existing = Get-AppxPackage -Name $id.PackageName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Output ("  removing existing " + $existing.PackageFullName)
        Remove-AppxPackage -Package $existing.PackageFullName
    }
    Add-AppxPackage -Path $msix
    $installed = Get-AppxPackage -Name $id.PackageName
    if (-not $installed) { throw "Add-AppxPackage reported success but the package is not present" }
    Write-Output ("  installed: " + $installed.PackageFullName)
    Write-Output ("  version  : " + $installed.Version)
    Write-Output ("  install  : " + $installed.InstallLocation)
    $installedExe = Get-ChildItem $installed.InstallLocation -Filter 'SA-Sur.exe' | Select-Object -First 1
    Write-Output ("  exe      : " + $installedExe.FullName + "  (" + $installedExe.VersionInfo.ProductVersion + ")")
}

Write-Output "== done =="
Write-Output ("artifact: " + $msix)
