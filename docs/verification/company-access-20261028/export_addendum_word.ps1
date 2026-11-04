param([Parameter(Mandatory=$true)][string]$InputPath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$word=$null
$document=$null
$ownsApplication=$false
try {
    $word=New-Object -ComObject Word.Application
    if ($word.Documents.Count -ne 0) { throw 'Word returned an application with existing documents; leaving it untouched.' }
    $ownsApplication=$true
    $word.Visible=$false
    $word.DisplayAlerts=0
    $word.AutomationSecurity=3
    $documentPath=[IO.Path]::GetFullPath($InputPath)
    $confirmConversions=$false
    $readOnly=$true
    $addToRecent=$false
    $document=$word.Documents.Open([ref]$documentPath,[ref]$confirmConversions,[ref]$readOnly,[ref]$addToRecent)
    $document.Fields.Update() | Out-Null
    $document.Repaginate()
    $document.ExportAsFixedFormat([IO.Path]::GetFullPath($OutputPath),17)
} finally {
    $saveChanges=0
    if ($null -ne $document) { try { $document.Close([ref]$saveChanges) } catch {}; [void][Runtime.InteropServices.Marshal]::ReleaseComObject($document) }
    if ($null -ne $word) {
        if ($ownsApplication) { try { $word.Quit([ref]$saveChanges) } catch {} }
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($word)
    }
}
