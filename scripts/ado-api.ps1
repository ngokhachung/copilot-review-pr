# Ham helper Azure DevOps REST API - dot-source de dung:  . .\scripts\ado-api.ps1
# Cac URL/body o day la dac ta chinh xac cho HTTP action trong agent flows.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\ado-env.ps1"

$script:B64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($env:ADO_PAT)"))
$script:RepoApi = "$($env:ADO_ORG_URL)/$($env:ADO_PROJECT)/_apis/git/repositories/$($env:ADO_REPO)"

function Invoke-Ado {
    param([string]$Method = 'GET', [string]$Uri, $Body = $null)
    $p = @{ Method = $Method; Uri = $Uri; ContentType = 'application/json'
            Headers = @{ Authorization = "Basic $script:B64" } }
    if ($null -ne $Body) { $p.Body = ($Body | ConvertTo-Json -Depth 10) }
    Invoke-RestMethod @p
}

function Get-PrMetadata { param([int]$PrId)
    Invoke-Ado -Uri "$script:RepoApi/pullRequests/$PrId`?api-version=7.1" }

function Get-PrLatestIterationId { param([int]$PrId)
    $r = Invoke-Ado -Uri "$script:RepoApi/pullRequests/$PrId/iterations?api-version=7.1"
    ($r.value | Select-Object -Last 1).id }

function Get-PrChanges { param([int]$PrId, [int]$IterationId)
    $r = Invoke-Ado -Uri "$script:RepoApi/pullRequests/$PrId/iterations/$IterationId/changes?`$compareTo=0&api-version=7.1"
    $r.changeEntries }

function Get-ItemContent { param([string]$Path, [string]$Branch)
    $r = Invoke-Ado -Uri ("$script:RepoApi/items?path=$([uri]::EscapeDataString($Path))" +
        "&versionDescriptor.version=$([uri]::EscapeDataString($Branch))" +
        "&versionDescriptor.versionType=branch&includeContent=true&api-version=7.1")
    $r.content }

function Get-PrThreads { param([int]$PrId)
    (Invoke-Ado -Uri "$script:RepoApi/pullRequests/$PrId/threads?api-version=7.1").value }

function New-PrInlineThread {
    param([int]$PrId, [string]$FilePath, [int]$Line, [string]$Content,
          [string]$Fingerprint, [string]$Rule = '')
    $body = @{
        comments      = @(@{ parentCommentId = 0; content = $Content; commentType = 1 })
        status        = 1
        threadContext = @{
            filePath       = $FilePath   # phai bat dau bang '/'
            rightFileStart = @{ line = $Line; offset = 1 }
            rightFileEnd   = @{ line = $Line; offset = 1 }
        }
        properties    = @{
            'prv.fingerprint' = @{ '$type' = 'System.String'; '$value' = $Fingerprint }
            'prv.rule'        = @{ '$type' = 'System.String'; '$value' = $Rule }
        }
    }
    Invoke-Ado -Method POST -Uri "$script:RepoApi/pullRequests/$PrId/threads?api-version=7.1" -Body $body }

function New-PrSummaryThread { param([int]$PrId, [string]$Content)
    $body = @{
        comments   = @(@{ parentCommentId = 0; content = $Content; commentType = 1 })
        status     = 1
        properties = @{ 'prv.summary' = @{ '$type' = 'System.String'; '$value' = 'true' } }
    }
    Invoke-Ado -Method POST -Uri "$script:RepoApi/pullRequests/$PrId/threads?api-version=7.1" -Body $body }

function Add-ThreadReply { param([int]$PrId, [int]$ThreadId, [string]$Content)
    Invoke-Ado -Method POST -Uri "$script:RepoApi/pullRequests/$PrId/threads/$ThreadId/comments?api-version=7.1" `
        -Body @{ parentCommentId = 1; content = $Content; commentType = 1 } }

function Set-ThreadStatus { param([int]$PrId, [int]$ThreadId, [string]$Status = 'fixed')
    Invoke-Ado -Method PATCH -Uri "$script:RepoApi/pullRequests/$PrId/threads/$ThreadId`?api-version=7.1" `
        -Body @{ status = $Status } }

function Update-ThreadComment { param([int]$PrId, [int]$ThreadId, [string]$Content)
    Invoke-Ado -Method PATCH -Uri "$script:RepoApi/pullRequests/$PrId/threads/$ThreadId/comments/1?api-version=7.1" `
        -Body @{ content = $Content } }
