using namespace YamlDotNet.RepresentationModel
using namespace System.IO

$ErrorActionPreference = "Stop"

$conString = ""
$apiKey = ""
$appKey = ""
$hostName = "Zaiba2"

$postURI = ("https://api.datadoghq.com/api/v1/series?api_key={0}&application_key={1}" -f $apiKey, $appKey)
$confPath = "./conf.d\*.yaml"
Add-Type -Path "./lib/YamlDotNet.dll"

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

$confFiles = Get-ChildItem -Path $confPath

foreach ($confFile in $confFiles) { 
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
    $con.Dispose()
    
    $body_detail = ""
    $postTime = (Get-Date -UFormat %s)
    foreach ($row in $dt.rows) { 
        if (!([System.String]::IsNullOrEmpty($body_detail))) {
            $body_detail += ", "
        }
        $body_detail += ($body_base -f `
                $conf.metrics_name,
            $postTime, 
            $row[[int]$conf.monitor_value_position],
            $hostName,
            $conf.dd_tags)    
    }
    
    $ret = Invoke-WebRequest -Uri $postURI -Method "Post" -Headers @{"Content-type" = "application/json" } -Body ($body_root -f $body_detail)    
    if ($ret.StatusCode -eq 202) {
        Write-Host "Metric Send Success."
    }
    else {
        Write-Host "Metric Send Error." -BackgroundColor Red
    }
}
