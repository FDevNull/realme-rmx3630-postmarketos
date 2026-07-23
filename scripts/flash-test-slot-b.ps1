[CmdletBinding()]
param(
    [string]$DumpsDir = 'C:\UnlockTool\fff',
    [string]$ImagePath = 'C:\Users\Valtos\Documents\Random\rmx3630-linux-port\out\rmx3630-alpine-test-boot.img'
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

$imageSize = (Get-Item -LiteralPath $ImagePath).Length
if ($imageSize -gt 64MB) {
    throw "Experimental boot image is larger than the 64 MiB boot partition: $imageSize"
}

$adbState = adb get-state 2>$null
if ($adbState -eq 'device') {
    Write-Host 'Entering fastbootd...'
    adb reboot fastboot
}

$seen = $false
for ($i = 0; $i -lt 90; $i++) {
    if (fastboot devices 2>$null) {
        $seen = $true
        break
    }
    Start-Sleep -Milliseconds 500
}
if (-not $seen) {
    throw 'The phone did not appear in fastbootd within 45 seconds.'
}

$userspace = (fastboot getvar is-userspace 2>&1 | Out-String)
$unlocked = (fastboot getvar unlocked 2>&1 | Out-String)
$currentSlot = (fastboot getvar current-slot 2>&1 | Out-String)
if ($userspace -notmatch 'is-userspace:\s*yes') {
    throw "Expected fastbootd, got: $userspace"
}
if ($unlocked -notmatch 'unlocked:\s*yes') {
    throw "Bootloader is not unlocked: $unlocked"
}
if ($currentSlot -notmatch 'current-slot:\s*a') {
    throw "Refusing to prepare slot B because current slot is not A: $currentSlot"
}

Write-Host 'Preparing inactive slot B with slot-A hardware images...'
fastboot flash vendor_boot_b (Join-Path $DumpsDir 'vendor_boot_a.img')
if ($LASTEXITCODE -ne 0) { throw 'vendor_boot_b flash failed' }
fastboot flash dtbo_b (Join-Path $DumpsDir 'dtbo_a.img')
if ($LASTEXITCODE -ne 0) { throw 'dtbo_b flash failed' }
fastboot --disable-verity --disable-verification flash vbmeta_b (Join-Path $DumpsDir 'vbmeta_a.img')
if ($LASTEXITCODE -ne 0) { throw 'vbmeta_b flash failed' }
fastboot flash boot_b $ImagePath
if ($LASTEXITCODE -ne 0) { throw 'boot_b flash failed' }

Write-Host 'Selecting slot B and booting the Alpine test image...'
fastboot set_active b
if ($LASTEXITCODE -ne 0) { throw 'Could not select slot B' }
fastboot reboot
if ($LASTEXITCODE -ne 0) { throw 'Reboot failed' }

Write-Host 'The phone should enumerate as USB RNDIS and request 172.16.42.x by DHCP.'
Write-Host 'Connect to the root shell with: telnet 172.16.42.1 23'
