param (
    [string]$inputFile #add as an arguMent
)

if (-not (Test-Path $inputFile)) {
    Write-Host "Error: Input file not found! Exiting script."
    exit
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$baseFileName = [System.IO.Path]::GetFileNameWithoutExtension($inputFile)
$outputFile = "C:\network_discovery\${baseFileName}_${timestamp}_nslookup_results.log"
$terminalOutputFile = "C:\network_discovery\${baseFileName}_${timestamp}_terminal_output.txt"

Write-Host "Logging results to: $outputFile"
Write-Host "Logging terminal output to: $terminalOutputFile"

$data = Import-Csv -Path $inputFile -Delimiter ","

Write-Host "Checking imported data..."
$data | Format-Table -AutoSize

# Extract unique server names from "path"
$servers = @{}

foreach ($entry in $data) {
    $path = $entry.path

    # Extract first and second words after the first slash
    if ($path -match "^/([^/]+)(?:/([^/]+))?") {
        $primaryServer = $matches[1]
        $secondaryServer = $matches[2]

        if (-not $servers.ContainsKey($primaryServer)) {
            $servers[$primaryServer] = $secondaryServer  # Store fallback server name
        }
    }
}

# Debugging: Print extracted server names
Write-Host "Extracted Server Names (with fallback if needed):"
$servers.GetEnumerator() | ForEach-Object { Write-Host "$($_.Key) -> $($_.Value)" }

"Timestamp, Server Name, Status, Message, Used Fallback" | Out-File -FilePath $outputFile
"Terminal Output Log" | Out-File -FilePath $terminalOutputFile

foreach ($serverEntry in $servers.GetEnumerator()) {
    $primaryServer = $serverEntry.Key
    $fallbackServer = $serverEntry.Value
    $usedFallback = $false
    $loggedServerName = $primaryServer

    function Run-Nslookup($server) {
        Write-Host "Running nslookup for: $server"
        $nslookupResult = nslookup $server 2>&1
        Write-Host "Result: $nslookupResult"

        if ($nslookupResult -match "Non-existent domain" -or $nslookupResult -match "can't find") {
            return @{ Status = "Failed"; Message = "Host not found" }
        } elseif ($nslookupResult -match "Name:" -or $nslookupResult -match "Address:") {
            return @{ Status = "Success"; Message = "Resolved" }
        } else {
            return @{ Status = "Failed"; Message = "Unknown error" }
        }
    }

    # First try the primary server
    $result = Run-Nslookup $primaryServer

    # If the first lookup fails and a fallback exists, try the fallback server
    if ($result.Status -eq "Failed" -and $fallbackServer) {
        Write-Host "Primary lookup failed. Trying fallback: $fallbackServer"
        $usedFallback = $true
        $result = Run-Nslookup $fallbackServer
        $loggedServerName = $fallbackServer  # Use fallback server name in log
    }

    # Log the final result with fallback info
    "$((Get-Date).ToString("yyyy-MM-dd HH:mm:ss")), $loggedServerName, $($result['Status']), $($result['Message']), $($usedFallback)" | Out-File -FilePath $outputFile -Append

    "$((Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) - Server: $loggedServerName`nnslookup $loggedServerName`nResult: $($result['Status']) - $($result['Message'])`nUsed Fallback: $($usedFallback)`n" | Out-File -FilePath $terminalOutputFile -Append
}

Write-Host "Script execution completed."
