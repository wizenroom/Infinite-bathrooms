# Dev tool: work around HTTP 408 on large pushes by uploading objects in
# small batches. Builds synthetic commits (base -> +chunk1 -> +chunk1+2 ...)
# on a temp remote branch so each push transfers ~25 MB, then pushes the real
# branch (server already has the blobs) and deletes the temp branch.
param(
    [string]$Base = "6b003b3",
    [string]$Target = "master",
    [long]$ChunkBytes = 25MB
)

$ErrorActionPreference = "Stop"
Set-Location "C:\Users\lenovo\Projects\gmtk-terragen"

$env:GIT_INDEX_FILE = "$PWD\.git\chunk-push-index"

# Start from the base tree the server already has.
git read-tree $Base
if ($LASTEXITCODE -ne 0) { throw "read-tree failed" }

# All files at target state, grouped into size-limited chunks.
# (Working tree is clean at $Target, so file contents match.)
$files = (git ls-tree -r --name-only -z $Target) -split "`0" | Where-Object { $_ -ne "" }

$chunks = @()
$current = @()
$currentSize = 0
foreach ($f in $files) {
    $size = (Get-Item -LiteralPath $f -ErrorAction SilentlyContinue).Length
    if ($null -eq $size) { $size = 0 }
    $current += $f
    $currentSize += $size
    if ($currentSize -ge $ChunkBytes) {
        $chunks += , $current
        $current = @()
        $currentSize = 0
    }
}
if ($current.Count -gt 0) { $chunks += , $current }

Write-Output "Uploading in $($chunks.Count) chunk(s)"

$prev = (git rev-parse $Base).Trim()
$i = 0
foreach ($chunk in $chunks) {
    $i++
    foreach ($f in $chunk) {
        git update-index --add -- "$f"
        if ($LASTEXITCODE -ne 0) { throw "update-index failed on $f" }
    }
    $tree = (git write-tree).Trim()
    $commit = (git commit-tree $tree -p $prev -m "chunk $i").Trim()
    Write-Output "chunk ${i}: pushing $commit"
    git push origin "${commit}:refs/heads/push-helper" 2>&1 | Select-Object -Last 1 | Out-String | Write-Output
    if ($LASTEXITCODE -ne 0) { throw "push of chunk $i failed" }
    $prev = $commit
}

Remove-Item Env:GIT_INDEX_FILE
Remove-Item "$PWD\.git\chunk-push-index" -ErrorAction SilentlyContinue

Write-Output "Pushing real branch..."
git push origin "${Target}:master" 2>&1 | Select-Object -Last 2 | Out-String | Write-Output
if ($LASTEXITCODE -ne 0) { throw "final push failed" }

Write-Output "Cleaning up temp branch..."
git push origin --delete push-helper 2>&1 | Select-Object -Last 1 | Out-String | Write-Output

git ls-remote origin master
Write-Output "DONE"
