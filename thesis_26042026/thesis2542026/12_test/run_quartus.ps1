param(
    [string]$ProjectDir = "..\06_FGPA_Imple\thesis",
    [string]$Revision = "thesis_v1",
    [ValidateSet("map", "fit", "asm", "sta", "full")]
    [string]$Stage = "map"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

. (Join-Path $scriptDir "quartus_env.ps1")

$projectAbs = Resolve-Path (Join-Path $scriptDir $ProjectDir)
Set-Location $projectAbs

$logDir = Join-Path $scriptDir "log"
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory | Out-Null
}

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $logDir ("quartus_{0}_{1}_{2}.log" -f $Revision, $Stage, $ts)

$cmd = $null
$args = @()

switch ($Stage) {
    "map"  { $cmd = "quartus_map"; $args = @($Revision, "-c", $Revision) }
    "fit"  { $cmd = "quartus_fit"; $args = @($Revision, "-c", $Revision) }
    "asm"  { $cmd = "quartus_asm"; $args = @($Revision, "-c", $Revision) }
    "sta"  { $cmd = "quartus_sta"; $args = @($Revision, "-c", $Revision) }
    "full" { $cmd = "quartus_sh";  $args = @("--flow", "compile", $Revision, "-c", $Revision) }
}

Write-Host "Running: $cmd $($args -join ' ')"
Write-Host "Log: $logFile"

& $cmd @args 2>&1 | Tee-Object -FilePath $logFile

$pythonScript = Join-Path $scriptDir "quartus_status.py"
if (Test-Path $pythonScript) {
    $pyCmd = $null
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $pyCmd = "python"
    } elseif (Get-Command py -ErrorAction SilentlyContinue) {
        $pyCmd = "py"
    }

    Write-Host "\nStatus summary:"
    if ($pyCmd) {
        & $pyCmd $pythonScript --log $logFile --report-dir (Join-Path $projectAbs "output_files") --revision $Revision --write-json (Join-Path $scriptDir "quartus_status.json")
    } else {
        Write-Host "Khong tim thay python/py trong PATH, bo qua buoc parse status."
    }
}

Write-Host "\nDone."
