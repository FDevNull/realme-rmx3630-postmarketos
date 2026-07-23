[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$adbState = adb get-state 2>$null
if ($adbState -eq 'device') {
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
    throw 'Enter fastbootd on the phone, then run this script again.'
}

fastboot set_active a
if ($LASTEXITCODE -ne 0) { throw 'Could not select stock slot A' }
fastboot reboot
if ($LASTEXITCODE -ne 0) { throw 'Reboot failed' }

Write-Host 'Stock slot A selected and reboot requested.'
