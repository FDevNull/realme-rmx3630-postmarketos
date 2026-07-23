[CmdletBinding()]
param(
    [string]$DumpsDir = 'C:\UnlockTool\fff',
    [string]$ImagePath = 'C:\Users\Valtos\Documents\Random\rmx3630-linux-port\out\rmx3630-halium-kernel-test-boot-v2.img'
)

$ErrorActionPreference = 'Stop'

foreach ($path in @(
    $ImagePath,
    (Join-Path $DumpsDir 'vendor_boot_a.img'),
    (Join-Path $DumpsDir 'dtbo_a.img'),
    (Join-Path $DumpsDir 'vbmeta_a.img')
)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing required image: $path"
    }
}

if ((Get-Item -LiteralPath $ImagePath).Length -gt 64MB) {
    throw 'Experimental boot image is larger than the 64 MiB boot partition.'
}

if ((adb get-state 2>$null) -eq 'device') {
    if ((adb shell getprop ro.boot.slot_suffix).Trim() -ne '_b') {
        throw 'Refusing to replace slot A unless rooted Android is running from slot B.'
    }
    adb reboot fastboot
}

$seen = $false
for ($i = 0; $i -lt 120; $i++) {
    if (fastboot devices 2>$null) {
        $seen = $true
        break
    }
    Start-Sleep -Milliseconds 500
}
if (-not $seen) { throw 'The phone did not appear in fastbootd.' }

$userspace = (fastboot getvar is-userspace 2>&1 | Out-String)
$currentSlot = (fastboot getvar current-slot 2>&1 | Out-String)
$slotBSuccessful = (fastboot getvar 'slot-successful:b' 2>&1 | Out-String)
if ($userspace -notmatch 'is-userspace:\s*yes') {
    throw "Expected fastbootd, got: $userspace"
}
if ($currentSlot -notmatch 'current-slot:\s*b') {
    throw "Expected rooted slot B, got: $currentSlot"
}
if ($slotBSuccessful -notmatch 'slot-successful:b:\s*yes') {
    throw "Rooted slot B is not marked successful: $slotBSuccessful"
}

Write-Host 'Preparing slot A for a logged Linux boot; rooted slot B stays intact...'
fastboot flash vendor_boot_a (Join-Path $DumpsDir 'vendor_boot_a.img')
if ($LASTEXITCODE -ne 0) { throw 'vendor_boot_a flash failed' }
fastboot flash dtbo_a (Join-Path $DumpsDir 'dtbo_a.img')
if ($LASTEXITCODE -ne 0) { throw 'dtbo_a flash failed' }
fastboot --disable-verity --disable-verification flash vbmeta_a (Join-Path $DumpsDir 'vbmeta_a.img')
if ($LASTEXITCODE -ne 0) { throw 'vbmeta_a flash failed' }
fastboot flash boot_a $ImagePath
if ($LASTEXITCODE -ne 0) { throw 'boot_a flash failed' }

fastboot set_active a
if ($LASTEXITCODE -ne 0) { throw 'Could not select slot A' }
fastboot reboot
if ($LASTEXITCODE -ne 0) { throw 'Reboot failed' }

Write-Host 'Linux test is booting from A; wait for automatic fallback to rooted B.'
