param (
    [string]$JsonUrl = "https://wko_architecture.test/storage/image_test_page.json",
    [int]$Concurrency = 3000,
    [int]$DurationSeconds = 30,
    [string]$LogFile = "results.csv"
)

Add-Type -AssemblyName System.Net.Http

# Fetch image URLs from remote JSON
try {
    $json = Invoke-WebRequest -Uri $JsonUrl -UseBasicParsing -TimeoutSec 10 | Select-Object -ExpandProperty Content
    $urls = ($json | ConvertFrom-Json).images
} catch {
    Write-Error "Failed to fetch or parse remote JSON from $JsonUrl"
    exit 1
}

if (-not $urls -or $urls.Count -eq 0) {
    Write-Error "No URLs found in JSON file from $JsonUrl"
    exit 1
}

# Create a shared HttpClient instance
$httpClient = New-Object System.Net.Http.HttpClient
$httpClient.Timeout = [TimeSpan]::FromSeconds(10)

# Create result list and lock
$syncRoot = New-Object Object
$results = New-Object System.Collections.Generic.List[Object]

# Timing control
$endTime = [datetime]::UtcNow.AddSeconds($DurationSeconds)

# Start runspaces
$runspacePool = [runspacefactory]::CreateRunspacePool(1, $Concurrency)
$runspacePool.Open()
$runspaces = @()

for ($i = 0; $i -lt $Concurrency; $i++) {
    $runspace = [powershell]::Create()
    $runspace.RunspacePool = $runspacePool

    $runspace.AddScript({
        param($urls, $endTime, $httpClient, $syncRoot, $results)

        while ([datetime]::UtcNow -lt $endTime) {
            $url = Get-Random -InputObject $urls
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $response = $httpClient.GetAsync($url).Result
                $sw.Stop()
                $status = if ($response.IsSuccessStatusCode) { "OK" } else { "FAIL" }
            } catch {
                $sw.Stop()
                $status = "ERROR"
            }

            $timestamp = [datetime]::UtcNow.ToString("o")
            $latency = [math]::Round($sw.Elapsed.TotalMilliseconds, 2)

            $entry = "$timestamp,$status,$latency"
            [System.Threading.Monitor]::Enter($syncRoot)
            try {
                $results.Add($entry)
            } finally {
                [System.Threading.Monitor]::Exit($syncRoot)
            }
        }
    }) | Out-Null

    $runspace.AddArgument($urls)
    $runspace.AddArgument($endTime)
    $runspace.AddArgument($httpClient)
    $runspace.AddArgument($syncRoot)
    $runspace.AddArgument($results)

    $runspaces += $runspace.BeginInvoke()
}

# Wait for all runspaces to complete
$runspaces | ForEach-Object { $_.AsyncWaitHandle.WaitOne() }

# Write results to CSV
"Timestamp,Status,LatencyMs" | Out-File -Encoding UTF8 $LogFile
$results | Out-File -Append -Encoding UTF8 $LogFile

$httpClient.Dispose()
$runspacePool.Close()
$runspacePool.Dispose()

Write-Host "`nTest complete. Results saved to $LogFile"