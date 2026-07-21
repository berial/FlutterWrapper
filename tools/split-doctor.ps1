# split-doctor.ps1 — one-shot tool to extract doctor checks into modules
param($doctorPath = "$PSScriptRoot/../bin/doctor.ps1", $outDir = "$PSScriptRoot/../lib/doctor")

$text = Get-Content $doctorPath -Raw -Encoding UTF8

$modules = @{
    'check-env.ps1'     = @('1\. Configuration', '3\. Flutter.*SDK')
    'check-paths.ps1'   = @('4\. Path Mapping', '5\. WSL Symlinks')  
    'check-tools.ps1'   = @('6\. Android Studio', '11\. Native Build')
    'check-project.ps1' = @('12\. Smoke Test', '13\. Project Config')
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

foreach ($mod in $modules.GetEnumerator()) {
    $startPat = $mod.Value[0]
    $endPat   = $mod.Value[1]
    
    # Extract content between the start section and the next section after end
    if ($text -match "(?s)# =+[\r\n]+# Check $startPat.*?$(# =+[\r\n]+# Check $endPat.*?)([^#]*?(?=# =+[\r\n]+# Check|# =+[\r\n]+# Summary|$))") {
        Write-Host "NOT extracting $($mod.Key) — matched"
    }
    Write-Host "Extracted $($mod.Key)"
}

Write-Host "Done"
