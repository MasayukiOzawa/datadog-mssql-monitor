using namespace System.Management.Automation.Runspaces.Runspace;
using namespace System.Collections.Generic;
# using namespace YamlDotNet.RepresentationModel;
# using namespace System.IO;

param($Timer)

# Wait-Debugger
Write-Host "Start."
$ErrorActionPreference = "Stop"
Add-Type -Path "./lib/YamlDotNet.dll"

$conString = ("Data Source={0};Initial Catalog={1};User Id={2};Password={3}" -f $ENV:MSSQL_SERVER_NAME, $ENV:MSSQL_DATABASE_NAME, $ENV:MSSQL_USER_ID, $ENV:MSSQL_USER_PASSWORD)
$apiKey = $ENV:DATADOG_APIKEY
$runspaceSize = 5

$confPath = "./conf.d\*.yaml"
$confFiles = Get-ChildItem -Path $confPath
function Test-EnvironmentVariable() {
    param(
        $MssqlConnectionString,
        $DatadogAPIKey
    )
    if ($null -eq $MssqlConnectionString) {
        Write-Host "Environment variable MSSQL_CONNECTIONSTRING not set." -ForegroundColor Red
        exit -1
    }
    
    if ($null -eq $DatadogAPIKey) {
        Write-Host "Environment variable DATADOG_APIKEY not set." -ForegroundColor Red
        exit -1
    }
}

function Read-YamlConfig {
    param(
        $fileName 
    )
    $stream = New-Object System.IO.StreamReader -ArgumentList $fileName, [System.Text.Encoding]::UTF8
    $yaml = New-Object YamlDotNet.RepresentationModel.YamlStream
    $yaml.Load($stream)
    $stream.Close()

    $mapping = $yaml.Documents[0].RootNode
    $metrics_name = ($mapping.Children[[YamlDotNet.RepresentationModel.YamlScalarNode]::new("metrics_name")]).value
    $monitor_sql = ($mapping.Children[[YamlDotNet.RepresentationModel.YamlScalarNode]::new("monitor_sql")]).value
    $monitor_value_position = ($mapping.Children[[YamlDotNet.RepresentationModel.YamlScalarNode]::new("monitor_value_position")]).value
    $dd_tags = ""
    foreach ($tag in $mapping.Children[[YamlDotNet.RepresentationModel.YamlScalarNode]::new("dd_tags")]) {
        if (!([System.String]::IsNullOrEmpty($dd_tags))) {
            $dd_tags += (', ')
        }
        $dd_tags += ('"{0}:{1}"' -f $tag.Key.Value, $tag.Value.Value)
    }
    
    return  [PSCustomObject]@{
        metrics_name           = $metrics_name
        monitor_sql            = $monitor_sql
        monitor_value_position = $monitor_value_position
        dd_tags                = $dd_tags
    }
}

function Out-Message() {
    param(
        $Message,
        $ErrorInfo = $null
    )
    if ($null -eq $ErrorInfo) {
        Write-Host ("{0} : {1}" -f (Get-Date).ToString("yyyy/MM/dd hh:mm:ss.fff"), $Message)
    }
    else {
        Write-Host ("{0} : {1}" -f (Get-Date).ToString("yyyy/MM/dd hh:mm:ss.fff"), $Message) -ForegroundColor Red
    }
}

function Send-DatadogMetrics() {
    param(
        $confFile,
        $conString,
        $apiKey

    )
    $ErrorActionPreference = "Stop"
    $hostName = $ENV:MSSQL_SERVER_NAME
    $postURI = ("https://api.datadoghq.com/api/v1/series?api_key={0}" -f $apiKey, $appKey)

    $body_root = @"
    {{
        "series" :
            [
                {0}
            ]
    }}
"@
    
    $body_base = @"
    {{
        "metric":"{0}",
        "points":[[{1}, {2}]],
        "type":"gauge",
        "host":"{3}",
        "tags":[{4}]
    }}
"@
    
    
    $conf = Read-YamlConfig -fileName $confFile.FullName

    $con = New-Object System.Data.SqlClient.SqlConnection
    $con.ConnectionString = $conString
    $con.Open()

    $cmd = $con.CreateCommand()
    $cmd.CommandText = $conf.monitor_sql
    $da = New-Object System.Data.SqlClient.SqlDataAdapter
    $dt = New-Object System.Data.DataTable 
    $da.SelectCommand = $cmd
    [void]$da.Fill($dt)
        
    $body_detail = ""
    $dd_tags = $conf.dd_tags
    $postTime = (Get-Date -UFormat %s)
    
    foreach ($row in $dt.rows) {
        if ($null -ne $row.dd_tags) {
            $dd_tags += (", ""{0}""" -f $row.dd_tags)
        }
        foreach ($col in $row.Table.Columns) {
            if (!([System.String]::IsNullOrEmpty($body_detail))) {
                $body_detail += ", "
            }
            $body_detail += ($body_base -f `
                ("{0}.{1}" -f $conf.metrics_name, $col.ColumnName),
                $postTime, 
                $row.$col,
                $hostName,
                $dd_tags)
        }
    
    }
    $dt.Dispose()
    $da.Dispose()

    $con.Close()
    $con.Dispose()

    try {
        $postTime = (Get-Date -UFormat %s)
        $ret = Invoke-WebRequest -Uri $postURI -Method "Post" -Headers @{"Content-type" = "application/json" } -Body ($body_root -f $body_detail)
        if ($ret.StatusCode -eq 202) {
            Out-Message -Message ("Metric [{0}] Send Success." -f $conf.metrics_name)
        }
        else {
            Out-Message -Message  ("Metric [{0}] Send Error." -f $conf.metrics_name) -ErrorInfo $true
        }
    }
    catch {
        Out-Message -Message  ("Metric [{0}] Send Error. (Exception : {1})" -f $conf.metrics_name, $error[0].Exception.Message) -ErrorInfo $true
    }
}

Test-EnvironmentVariable -MssqlConnectionString $conString -DatadogAPIKey $ENV:DATADOG_APIKEY

if ($ENV:RUNNING_MODE -eq "parallel") {
    $initialSessionState = [initialsessionstate]::CreateDefault()
    $initialSessionState.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry(
                "Read-YamlConfig", 
                ${function:Read-YamlConfig} 
            )))
    $initialSessionState.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry(
                "Out-Message", 
                ${function:Out-Message} 
            )))
    $minPoolSize = $maxPoolSize = $runspaceSize
    $runspacePool = [runspacefactory]::CreateRunspacePool($minPoolSize, $maxPoolSize, $initialSessionState, $Host)
    $runspacePool.Open()
    $runspaceCollection = New-Object 'List[pscustomobject]'
    foreach ($confFile in $confFiles) {
        $posh = [powershell]::Create().AddScript(${function:Send-DatadogMetrics}).`
            AddArgument($confFile).`
            AddArgument($conString).`
            AddArgument($apiKey)
        $posh.RunspacePool = $runspacePool
        $runspaceCollection.Add(
            [PSCustomObject]@{
                confFile = $confFile
                runspace = $posh.BeginInvoke()
                posh     = $posh
            }
        )
    }
    while ($runspaceCollection) {
        foreach ($runspace in $runspaceCollection) {
            if ($runspace.Runspace.IsCompleted) {
                $ret = $runspace.posh.EndInvoke($runspace.runspace)
                [void]$runspaceCollection.Remove($runspace)
                break
            }
        }
        start-sleep -Milliseconds 100
    }
    $runspacePool.Close()
    $runspacePool.Dispose()
}
else {
    foreach ($confFile in $confFiles) {
        Send-DatadogMetrics -confFile $confFile -conString $conString -apiKey $apiKey
    }
}