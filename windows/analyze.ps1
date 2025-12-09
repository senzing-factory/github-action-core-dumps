# windows/analyze.ps1
param(
    [string]$suffix = "windows"
)

Write-Host "Searching for crash dumps..."

$dumpDir = "$env:GITHUB_WORKSPACE\crash-dumps"
$systemDumpDir = "$env:LOCALAPPDATA\CrashDumps"
$werDumpDir = "C:\ProgramData\Microsoft\Windows\WER\ReportQueue"

# Find all dump files
$dumpFiles = @()
$dumpFiles += Get-ChildItem -Path $dumpDir -Filter "*.dmp" -Recurse -ErrorAction SilentlyContinue
$dumpFiles += Get-ChildItem -Path $systemDumpDir -Filter "*.dmp" -Recurse -ErrorAction SilentlyContinue
$dumpFiles += Get-ChildItem -Path $werDumpDir -Filter "*.dmp" -Recurse -ErrorAction SilentlyContinue

if ($dumpFiles.Count -eq 0) {
    Write-Host "✓ No crash dumps found"
    exit 0
}

Write-Host "⚠️  Found $($dumpFiles.Count) crash dump(s):"
$dumpFiles | ForEach-Object { Write-Host "  - $($_.FullName)" }

# Install debugging tools if not present
$cdbPath = "C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe"
if (-not (Test-Path $cdbPath)) {
    Write-Host "Installing Windows Debugging Tools..."
    # GitHub Actions windows runners should have this pre-installed
    # If not, we can download the SDK
    Write-Warning "cdb.exe not found. Install Windows SDK for debugging."
    $cdbPath = $null
}

# Analyze each dump
$analyzeDir = "$env:GITHUB_WORKSPACE\crash-analysis"
New-Item -ItemType Directory -Force -Path $analyzeDir | Out-Null

$dumpIndex = 0
foreach ($dump in $dumpFiles) {
    $dumpIndex++
    $outputFile = "$analyzeDir\analysis-$suffix-$dumpIndex.txt"
    
    Write-Host "`nAnalyzing: $($dump.Name)"
    
    # Determine executable type
    $exeName = $dump.BaseName -replace '\..*$'
    $isGo = $exeName -match 'go' -or $exeName -match '\.exe$'
    $isPython = $exeName -match 'python'
    $isDotNet = $exeName -match 'dotnet' -or $exeName -match '\.dll'
    
    # Basic info
    @"
================================================================================
CRASH DUMP ANALYSIS
================================================================================
Dump File: $($dump.FullName)
Size: $([math]::Round($dump.Length / 1MB, 2)) MB
Created: $($dump.CreationTime)
Type: $(if ($isGo) { "Go" } elseif ($isPython) { "Python" } elseif ($isDotNet) { ".NET" } else { "Native" })

"@ | Out-File -FilePath $outputFile -Encoding UTF8
    
    if ($cdbPath) {
        # Create debugger script
        $script = @"
.sympath srv*https://msdl.microsoft.com/download/symbols
.reload
!analyze -v
~*k
q
"@
        $scriptFile = "$analyzeDir\dbg-script-$dumpIndex.txt"
        $script | Out-File -FilePath $scriptFile -Encoding ASCII
        
        # Run debugger
        try {
            $output = & $cdbPath -z $dump.FullName -c "`$<$scriptFile" 2>&1
            $output | Out-File -FilePath $outputFile -Append -Encoding UTF8
        } catch {
            "ERROR: Failed to analyze dump: $_" | Out-File -FilePath $outputFile -Append
        }
    } else {
        "WARNING: cdb.exe not available. Unable to perform detailed analysis." | Out-File -FilePath $outputFile -Append
        
        # Provide basic file info instead
        "File Details:" | Out-File -FilePath $outputFile -Append
        Get-Item $dump.FullName | Format-List | Out-File -FilePath $outputFile -Append
    }
    
    Write-Host "  → Analysis saved to: $outputFile"
}

# Copy dumps to analysis directory for artifact upload
Write-Host "`nCopying dumps to analysis directory..."
$dumpFiles | ForEach-Object {
    Copy-Item $_.FullName -Destination $analyzeDir
}

Write-Host "`n✓ Analysis complete. Files ready for upload in: $analyzeDir"
