[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$KindleRoot,
    [switch]$ClearLog,
    [switch]$Eject
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$kindle = (Resolve-Path -LiteralPath $KindleRoot).Path
$documents = Join-Path $kindle 'documents'
$extensions = Join-Path $kindle 'extensions'

if (-not (Test-Path -LiteralPath $documents -PathType Container)) {
    throw "Kindle root validation failed: missing documents directory at $documents"
}
if (-not (Test-Path -LiteralPath $extensions -PathType Container)) {
    throw "Kindle root validation failed: missing extensions directory at $extensions"
}

$sourceLauncher = Join-Path $projectRoot 'documents\RecipeViewer.sh'
$sourceBundle = Join-Path $projectRoot 'extensions\RecipeViewer'
$sourceLibrary = Join-Path $projectRoot 'build\library'
$manifest = Join-Path $sourceLibrary 'manifest.tsv'
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "Compiled library not found. Run: python tools/compile_paprika.py <archive> --output build/library"
}

$destinationLauncher = Join-Path $documents 'RecipeViewer.sh'
$destinationBundle = Join-Path $extensions 'RecipeViewer'
$destinationLibrary = Join-Path $destinationBundle 'library'

if ($PSCmdlet.ShouldProcess($kindle, 'Deploy Recipe Viewer and verify every byte')) {
    New-Item -ItemType Directory -Force -Path $destinationBundle, $destinationLibrary | Out-Null
    Copy-Item -LiteralPath $sourceLauncher -Destination $destinationLauncher -Force

    Get-ChildItem -LiteralPath $sourceBundle -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($sourceBundle.Length).TrimStart('\', '/')
        $target = Join-Path $destinationBundle $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    }
    Get-ChildItem -LiteralPath $sourceLibrary -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destinationLibrary $_.Name) -Force
    }

    if ($ClearLog) {
        $log = Join-Path $destinationBundle 'debug.log'
        if (Test-Path -LiteralPath $log -PathType Leaf) {
            Remove-Item -LiteralPath $log -Force
        }
    }

    $pairs = @([PSCustomObject]@{ Source = $sourceLauncher; Destination = $destinationLauncher })
    Get-ChildItem -LiteralPath $sourceBundle -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($sourceBundle.Length).TrimStart('\', '/')
        $pairs += [PSCustomObject]@{
            Source = $_.FullName
            Destination = (Join-Path $destinationBundle $relative)
        }
    }
    Get-ChildItem -LiteralPath $sourceLibrary -File | ForEach-Object {
        $pairs += [PSCustomObject]@{
            Source = $_.FullName
            Destination = (Join-Path $destinationLibrary $_.Name)
        }
    }
    foreach ($pair in $pairs) {
        $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $pair.Source).Hash
        $destinationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $pair.Destination).Hash
        if ($sourceHash -ne $destinationHash) {
            throw "Byte verification failed: $($pair.Destination)"
        }
    }
    Write-Host "Verified $($pairs.Count) deployed files byte-for-byte."

    if ($Eject) {
        $driveRoot = [System.IO.Path]::GetPathRoot($kindle).TrimEnd('\')
        $shell = New-Object -ComObject Shell.Application
        $drive = $shell.Namespace(17).ParseName($driveRoot)
        if ($null -eq $drive) { throw "Could not locate $driveRoot for safe ejection" }
        $drive.InvokeVerb('Eject')
        Write-Host "Requested safe ejection of $driveRoot."
    } else {
        Write-Host 'Deployment verified. Eject the Kindle safely before unplugging it.'
    }
}
