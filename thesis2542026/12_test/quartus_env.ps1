param(
    [switch]$Persist
)

$ErrorActionPreference = "Stop"

function Get-QuartusBinDir {
    $candidates = @()

    if ($env:QUARTUS_ROOTDIR) {
        $root = $env:QUARTUS_ROOTDIR
        $candidates += (Join-Path $root "bin64")
        $candidates += (Join-Path $root "bin")
    }

    foreach ($base in @("C:\intelFPGA_lite", "C:\intelFPGA")) {
        if (Test-Path $base) {
            $versions = Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
            foreach ($v in $versions) {
                $candidates += (Join-Path $v.FullName "quartus\bin64")
                $candidates += (Join-Path $v.FullName "quartus\bin")
            }
        }
    }

    foreach ($dir in $candidates | Select-Object -Unique) {
        if (Test-Path (Join-Path $dir "quartus_sh.exe")) {
            return $dir
        }
    }

    return $null
}

$binDir = Get-QuartusBinDir
if (-not $binDir) {
    Write-Error "Khong tim thay quartus_sh.exe. Hay cai Quartus hoac sua PATH/QUARTUS_ROOTDIR."
}

if ($env:Path -notlike "*$binDir*") {
    $env:Path = "$binDir;$env:Path"
}

if ($Persist) {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$binDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$binDir;$userPath", "User")
        Write-Host "Da luu Quartus vao User PATH: $binDir"
    }
}

Write-Host "Quartus bin: $binDir"
& (Join-Path $binDir "quartus_sh.exe") --version
