# windows/enable.ps1
# Enable Windows Error Reporting to generate crash dumps

Write-Host "Configuring Windows crash dump collection..."

# Create crash dump directory
$dumpDir = "$env:GITHUB_WORKSPACE\crash-dumps"
New-Item -ItemType Directory -Force -Path $dumpDir | Out-Null

# Enable Windows Error Reporting (WER) to create dumps
$werKey = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"
$localDumpsKey = "$werKey\LocalDumps"

# Create LocalDumps registry key if it doesn't exist
if (-not (Test-Path $localDumpsKey)) {
    New-Item -Path $localDumpsKey -Force | Out-Null
}

# Configure dump settings
Set-ItemProperty -Path $localDumpsKey -Name "DumpFolder" -Value $dumpDir -Type ExpandString
Set-ItemProperty -Path $localDumpsKey -Name "DumpCount" -Value 10 -Type DWord
Set-ItemProperty -Path $localDumpsKey -Name "DumpType" -Value 2 -Type DWord  # 2 = Full dump

# For .NET applications, enable crash dumps
$env:COMPlus_DbgEnableMiniDump = "1"
$env:COMPlus_DbgMiniDumpType = "4"  # Full heap dump
$env:COMPlus_DbgMiniDumpName = "$dumpDir\dump_%p_%t.dmp"

Write-Host "✓ Crash dumps enabled at: $dumpDir"
Write-Host "  - Registry configured for native dumps"
Write-Host "  - Environment variables set for .NET dumps"

# Export environment variables for later steps
Add-Content $env:GITHUB_ENV "CRASH_DUMP_DIR=$dumpDir"
Add-Content $env:GITHUB_ENV "COMPlus_DbgEnableMiniDump=1"
Add-Content $env:GITHUB_ENV "COMPlus_DbgMiniDumpType=4"
Add-Content $env:GITHUB_ENV "COMPlus_DbgMiniDumpName=$dumpDir\dump_%p_%t.dmp"
