using namespace YamlDotNet.RepresentationModel
using namespace System.IO
$ErrorActionPreference = "Stop"

Add-Type -Path "./lib/YamlDotNet.dll"

$conString = $ENV:MSSQL_CONNECTIONSTRING
$apiKey = $ENV:DATADOG_APIKEY
$hostName = $ENV:COMPUTERNAME

$confPath = "./conf.d\*.yaml"
$confFiles = Get-ChildItem -Path $confPath
$postURI = ("https://api.datadoghq.com/api/v1/series?api_key={0}" -f $apiKey, $appKey)

if ($null -eq $conString) {
    Write-Host "Environment variable MSSQL_CONNECTIONSTRING not set." -BackgroundColor Red
    exit -1
}

if ($null -eq $apiKey) {
    Write-Host "Environment variable DATADOG_APIKEY not set." -BackgroundColor Red
    exit -1
}

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
    "metric":" {0}",
    "points":[[{1}, {2}]],
    "type":"gauge",
    "host":"{3}",
    "tags":[{4}]
}}
"@

function Read-YamlConfig {
    param(
        $fileName 
    )
    $stream = New-Object StreamReader -ArgumentList $fileName, [System.Text.Encoding]::UTF8
    $yaml = New-Object YamlStream
    $yaml.Load($stream)
    $stream.Close()

    $mapping = $yaml.Documents[0].RootNode
    $metrics_name = ($mapping.Children[[YamlScalarNode]::new("metrics_name")]).value
    $monitor_sql = ($mapping.Children[[YamlScalarNode]::new("monitor_sql")]).value
    $monitor_value_position = ($mapping.Children[[YamlScalarNode]::new("monitor_value_position")]).value

    $dd_tags = ""
    foreach ($tag in $mapping.Children[[YamlScalarNode]::new("dd_tags")]) {
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

$con = New-Object System.Data.SqlClient.SqlConnection
$con.ConnectionString = $conString
$con.Open()


foreach ($confFile in $confFiles) { 
    $conf = Read-YamlConfig -fileName $confFile.FullName
    $cmd = $con.CreateCommand()
    $cmd.CommandText = $conf.monitor_sql
    $da = New-Object System.Data.SqlClient.SqlDataAdapter
    $dt = New-Object System.Data.DataTable 
    $da.SelectCommand = $cmd
    [void]$da.Fill($dt)
    
    $body_detail = ""
    $postTime = (Get-Date -UFormat %s)
    $dd_tags = $conf.dd_tags

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

    try {
        $ret = Invoke-WebRequest -Uri $postURI -Method "Post" -Headers @{"Content-type" = "application/json" } -Body ($body_root -f $body_detail)
        if ($ret.StatusCode -eq 202) {
            Write-Host "Metric Send Success."
        }
        else {
            Write-Host "Metric Send Error." -BackgroundColor Red
        }
    }
    catch {
        Write-Host ("Metric Send Error. (Exception : {0})" -f $error[0].Exception.Message) -BackgroundColor Red
    }
}

$con.Close()
$con.Dispose()
