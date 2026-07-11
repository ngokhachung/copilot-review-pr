# Copy file này thành scripts/ado-env.ps1 (đã gitignore) rồi điền giá trị thật.
# KHÔNG commit ado-env.ps1.
$env:ADO_ORG_URL = 'https://dev.azure.com/yourorg'
$env:ADO_PROJECT = 'YourProject'
$env:ADO_REPO    = 'your-repo-name'   # tên hoặc GUID của pilot repo
$env:ADO_PAT     = 'xxxxxxxxxxxxxxxx' # PAT của svc-pr-review, scope Code R&W
