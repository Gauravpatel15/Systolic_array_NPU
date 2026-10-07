param([string]$VivadoBin = 'D:\Vivado\Vivado\2024.2\bin')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$testDir = Join-Path $projectRoot 'build\xsim'
New-Item -ItemType Directory -Force -Path $testDir | Out-Null
Copy-Item -Path (Join-Path $projectRoot 'sim\vectors\*.mem') -Destination $testDir -Force
Set-Content -LiteralPath (Join-Path $testDir 'run.tcl') -Encoding ascii -Value "run all`nquit"
Push-Location $testDir
try {
    & (Join-Path $VivadoBin 'xvlog.bat') -sv (Join-Path $projectRoot 'rtl\mac_pe.sv') (Join-Path $projectRoot 'rtl\systolic_array.sv') (Join-Path $projectRoot 'sim\tb_mac_pe.sv') (Join-Path $projectRoot 'sim\tb_systolic_array.sv')
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
    foreach ($testTop in @('tb_mac_pe','tb_systolic_array')) {
        & (Join-Path $VivadoBin 'xelab.bat') $testTop -s $testTop -debug typical
        if ($LASTEXITCODE -ne 0) { throw "xelab failed: $testTop" }
        $simOutput = & (Join-Path $VivadoBin 'xsim.bat') $testTop -tclbatch run.tcl -log "$testTop.log" 2>&1
        $simExit = $LASTEXITCODE
        $simOutput | ForEach-Object { Write-Output $_ }
        $logText = Get-Content -Raw -LiteralPath "$testTop.log"
        if ($simExit -ne 0 -or $logText -notmatch "PASS ${testTop}:" -or $logText -match '(?im)^\s*(Fatal:|ERROR:)') {
            throw "Simulation failed or PASS missing: $testTop"
        }
    }
    Write-Output 'ALL TESTS PASSED'
} finally { Pop-Location }
