param(
    [string] $Url = "https://mirror.twds.com.tw/centos-stream/10-stream/BaseOS/x86_64/iso/CentOS-Stream-10-latest-x86_64-dvd1.iso",
    [int] $ParallelDownloads = 3,
    [switch] $SimulateOnly,
    [int64] $SimulateBytesPerSecond = 50MB,
    [string] $ApiEndpoint = "",
    [string] $DeviceName = $env:COMPUTERNAME
)

# 預設為真實下載模式，除非指定 -SimulateOnly
$AllowExternalDownload = -not $SimulateOnly

if ($AllowExternalDownload) {
    Write-Host "真實下載模式已啟用。" -ForegroundColor Green
    Write-Host "目標: $Url" -ForegroundColor Cyan
} else {
    Write-Warning "模擬模式 - 無實際網路流量"
}

Write-Host "----------------------------------------"
Write-Host "TWDS 流量測試" -ForegroundColor Yellow
Write-Host "----------------------------------------"
$modeStr = if ($AllowExternalDownload) { "真實下載" } else { "模擬模式" }
Write-Host ("模式: {0}" -f $modeStr) -ForegroundColor $(if ($AllowExternalDownload) { "Green" } else { "Yellow" })
Write-Host "目標 URL: $Url"
Write-Host ("平行下載數: {0}" -f $ParallelDownloads)
Write-Host ("裝置名稱: {0}" -f $DeviceName)
if ($ApiEndpoint) {
    Write-Host ("API 端點: {0}" -f $ApiEndpoint) -ForegroundColor Cyan
} else {
    Write-Host "API 端點: 未設定（僅本地統計）" -ForegroundColor Gray
}
Write-Host "按 Ctrl+C 停止"
Write-Host "----------------------------------------"

# helper: format size (GB when >=1GB)
function Format-Size([long]$bytes) {
    if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
    elseif ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
    elseif ($bytes -ge 1KB) { return "{0:N2} KB" -f ($bytes / 1KB) }
    else { return "{0} B" -f $bytes }
}

# logfile for simulated workers to report (only used in simulate mode)
$logFile = Join-Path $env:TEMP "twds_sizes.log"
Remove-Item -Path $logFile -ErrorAction SilentlyContinue

# Worker scriptblock (same for both modes, but behaviour depends on $allowReal)
$worker = {
    param($url, $logfile, $simBytes, $allowReal)
    if ($allowReal) {
        while ($true) {
            try {
                # curl.exe prints size_download; -s silent, -L follow redirects, -o NUL discard
                $out = & curl.exe -s -L -o NUL -w "%{size_download}" $url 2>$null
                $size = 0
                if ([Int64]::TryParse($out, [ref]$size)) {
                    # append the size as a line
                    Add-Content -Path $logfile -Value $size
                } else {
                    # fallback: append 0 to indicate activity
                    Add-Content -Path $logfile -Value 0
                }
            } catch {
                Start-Sleep -Seconds 1
            }
        }
    } else {
        while ($true) {
            Start-Sleep -Seconds 1
            Add-Content -Path $logfile -Value $simBytes
        }
    }
}

# Start background jobs
$jobs = @()
for ($i = 1; $i -le $ParallelDownloads; $i++) {
    $jobs += Start-Job -ScriptBlock $worker -ArgumentList $Url,$logFile,$SimulateBytesPerSecond,$AllowExternalDownload
}

# If real mode: pick network adapter and capture baseline
$useNetStats = $AllowExternalDownload
$baselineRx = 0L
$baselineTx = 0L
$netAdapterName = $null

if ($useNetStats) {
    # choose first Up adapter with non-zero statistics
    $ad = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
    if ($null -eq $ad) {
        Write-Warning "未找到 Up 的網路介面，將改用模擬/檔案回報方式。"
        $useNetStats = $false
    } else {
        $netAdapterName = $ad.Name
        # get initial statistics
        $stat = Get-NetAdapterStatistics -Name $netAdapterName
        $baselineRx = [int64]$stat.ReceivedBytes
        $baselineTx = [int64]$stat.SentBytes
        Write-Host ("選擇網卡: {0} (baseline RX={1}, TX={2})" -f $netAdapterName, $baselineRx, $baselineTx)
    }
}

# aggregator totals (used if not using netstats)
$TotalRx = 0L
$TotalTx = 0L

$prevTotalRx = 0L
$prevTotalTx = 0L

# API reporting interval (every 5 seconds)
$lastApiReport = [DateTime]::Now
$apiReportInterval = 5

# Function to report to API
function Send-TrafficReport {
    param($endpoint, $device, $rx, $tx, $rxSpeed, $txSpeed)
    if (-not $endpoint) { return }

    try {
        $body = @{
            device = $device
            totalRx = $rx
            totalTx = $tx
            rxSpeed = $rxSpeed
            txSpeed = $txSpeed
            timestamp = [DateTime]::UtcNow.ToString("o")
        } | ConvertTo-Json

        Invoke-RestMethod -Uri "$endpoint/api/report" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 5 -ErrorAction SilentlyContinue | Out-Null
    } catch {
        # Silently ignore API errors to not disrupt main functionality
    }
}

try {
    while ($true) {
        Start-Sleep -Seconds 1

        if ($useNetStats) {
            # read current net stats and compute script-local totals by subtracting baseline
            try {
                $s = Get-NetAdapterStatistics -Name $netAdapterName
                $nowRx = [int64]$s.ReceivedBytes
                $nowTx = [int64]$s.SentBytes

                # totals relative to baseline
                $TotalRx = $nowRx - $baselineRx
                $TotalTx = $nowTx - $baselineTx

            } catch {
                # if reading netstats fails, fall back to file-based aggregation
                $useNetStats = $false
            }
        }

        if (-not $useNetStats) {
            # consume logfile entries (simulate or curl writes)
            if (Test-Path $logFile) {
                # read all lines atomically
                try {
                    $lines = Get-Content -Path $logFile -ErrorAction Stop
                    if ($lines.Count -gt 0) {
                        $sum = 0L
                        foreach ($l in $lines) {
                            [int64]$v = 0
                            if ([Int64]::TryParse($l, [ref]$v)) { $sum += $v }
                        }
                        $TotalRx += $sum
                        # approximate TX as small fraction
                        if ($AllowExternalDownload) {
                            $TotalTx += [int64]([math]::Round($sum * 0.001))
                        } else {
                            $TotalTx += [int64]([math]::Round($sum * 0.01))
                        }
                        # clear file after consuming
                        Clear-Content -Path $logFile -ErrorAction SilentlyContinue
                    }
                } catch {
                    # if file locked, skip this second
                }
            }
        }

        # compute per-second deltas
        $rxDelta = $TotalRx - $prevTotalRx
        $txDelta = $TotalTx - $prevTotalTx
        $prevTotalRx = $TotalRx
        $prevTotalTx = $TotalTx

        $totalRxStr = Format-Size $TotalRx
        $totalTxStr = Format-Size $TotalTx
        $rxSpeedStr = (Format-Size $rxDelta) + "/s"
        $txSpeedStr = (Format-Size $txDelta) + "/s"

        # Report to API every N seconds
        $now = [DateTime]::Now
        if ($ApiEndpoint -and ($now - $lastApiReport).TotalSeconds -ge $apiReportInterval) {
            Send-TrafficReport -endpoint $ApiEndpoint -device $DeviceName -rx $TotalRx -tx $TotalTx -rxSpeed $rxDelta -txSpeed $txDelta
            $lastApiReport = $now
        }

        # overwrite single line: use carriage return + no new line to mimic live update
        $outLine = "下載: {0} ({1}) | 上傳: {2} ({3})" -f $totalRxStr, $rxSpeedStr, $totalTxStr, $txSpeedStr
        Write-Host $outLine
    }
} catch [System.Exception] {
    Write-Host "偵測到中止：$_"
} finally {
    # Send final report before exiting
    if ($ApiEndpoint) {
        Send-TrafficReport -endpoint $ApiEndpoint -device $DeviceName -rx $TotalRx -tx $TotalTx -rxSpeed 0 -txSpeed 0
    }
    Get-Job | Where-Object { $_.State -eq 'Running' } | Stop-Job -Force -ErrorAction SilentlyContinue
    Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $logFile -ErrorAction SilentlyContinue
}
