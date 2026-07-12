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

# (Check .review/rules.md da bo - rule doc tu trang OneNote, amendment 2026-07-12b)

if ($fail) { exit 1 } else { Write-Host 'OK: PAT va quyen truy cap hop le.' }
