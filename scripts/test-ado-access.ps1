# Kiểm tra PAT + quyền truy cập pilot repo. Chạy: .\scripts\test-ado-access.ps1
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\ado-env.ps1"

$b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($env:ADO_PAT)"))
$headers = @{ Authorization = "Basic $b64" }
$repoApi = "$($env:ADO_ORG_URL)/$($env:ADO_PROJECT)/_apis/git/repositories/$($env:ADO_REPO)"
$fail = $false

try {
    $repo = Invoke-RestMethod -Uri "$repoApi`?api-version=7.1" -Headers $headers
    Write-Host "PASS: repo '$($repo.name)' (id $($repo.id), default branch $($repo.defaultBranch))"
} catch { Write-Host "FAIL: khong doc duoc repo - $($_.Exception.Message)"; $fail = $true }

try {
    $prs = Invoke-RestMethod -Uri "$repoApi/pullRequests?searchCriteria.status=active&api-version=7.1" -Headers $headers
    Write-Host "PASS: liet ke PR active - $($prs.count) PR"
} catch { Write-Host "FAIL: khong liet ke duoc PR - $($_.Exception.Message)"; $fail = $true }

try {
    $rules = Invoke-RestMethod -Uri "$repoApi/items?path=.review/rules.md&includeContent=true&`$format=json&api-version=7.1" -Headers $headers
    Write-Host "PASS: doc duoc .review/rules.md ($($rules.content.Length) ky tu)"
} catch { Write-Host "WARN: chua co .review/rules.md (se tao o Task 3)" }

if ($fail) { exit 1 } else { Write-Host 'OK: PAT va quyen truy cap hop le.' }
