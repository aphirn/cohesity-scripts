### usage: ./generateLicenseReport.ps1 -clusterList <file.txt> -username admin [ -domain local ] [-perjobstats true/false] 

### Simple script to generate license consumed report. Requires Cohesity OS 6.4+ - Jussi Jaurola <jussi@cohesity.com>

### clusterlist contains cluster name/ip per line


### process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$clusterList,
    [Parameter(Mandatory = $True)][string]$username,
    [Parameter()][string]$domain = 'local',
    [Parameter()][ValidateSet('true','false')][string]$perjobstats = "false"
)

### source the cohesity-api helper code
. ./cohesity-api

$clusters = Get-Content $clusterList

foreach ($cluster in $clusters)
{
    ### authenticate
    apiauth -vip $cluster -username $username -domain $domain

    ### check version
    $currentCluster = api get cluster
    $clusterSoftwareVersion = $currentCluster.clusterSoftwareVersion.SubString(0,3)

    if ($clusterSoftwareVersion -lt "6.4") {
        Write-Host "Cluster software needs to be 6.4 or higher to get metrics!" -ForegroundColor Red
    }

    ### get platform 
    $nodes = api get /nodes
    $hddCapacity = $nodes.capacityByTier | where-object { $_.storageTier -eq 'SATA-HDD'}
    $platformLicenseTotal = 0
    foreach ($hdd in $hddCapacity) 
    {
        $platformLicenseTotal += $hdd.tierMaxPhysicalCapacityBytes
    }

    ### get statistics
    $protectionStats = api get "stats/consumers?allUnderHierarchy=true&consumerType=kProtectionRuns"

    # get view protection jobs
    $viewProtectionJobs = api get protectionJobs?allUnderHierarchy=true | where-object { $_.environment -eq 'kView' }

    $viewNames = @()
    foreach ($viewName in $viewProtectionJobs.name)
    {
        $viewNames += $viewName

    }

    $statsWithoutViewJobs = $protectionStats.statsList | Where-Object { $_.name -notmatch ('(' + [string]::Join(')|(', $viewNames) + ')') }

    $totalLocalWrittenBytes = 0
    $totalCloudWrittenBytes= 0
    $storageConsumedBytes = 0

    if ($perjobstats -eq 'true') {Write-Host "License consumed per job:"}

    foreach ($job in $statsWithoutViewJobs)
    {
        $totalLocalWrittenBytes += $job.stats.localDataWrittenBytes
        $totalCloudWrittenBytes += $job.stats.cloudDataWrittenBytes
        $storageConsumedBytes += $job.stats.storageConsumedBytes
        
        if ($perjobstats -eq 'true') {
            Write-Host "Protection Job: $($job.name)" -ForegroundColor Yellow
            Write-Host "DataProtect:  $([math]::Round($job.stats.localDataWrittenBytes/1024/1024/1024)) GiB" -ForegroundColor Yellow
            Write-Host "CloudArchive: $([math]::Round($job.stats.cloudDataWrittenBytes/1024/1024/1024)) GiB" -ForegroundColor Yellow
            Write-Host "----------------------------------------------"
        }
    }

    Write-Host "Cluster $($currentCluster.name) ($($currentCluster.id)) Total statistics:"
    Write-Host "DataProtect:  $([math]::Round($totalLocalWrittenBytes/1024/1024/1024)) GiB" 
    Write-Host "CloudArchive: $([math]::Round($totalCloudWrittenBytes/1024/1024/1024)) GiB" 
    Write-Host "DataPlatform: $([math]::Round($platformLicenseTotal/1024/1024/1024)) GiB" 
}
