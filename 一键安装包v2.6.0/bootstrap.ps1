# 皮皮模组管理器 Bootstrap v3.0.1
# 从云端拉取最新安装脚本，失败则使用本地脚本
# v3.0.1: 保留版本探测，并在 Windows Terminal 下自动切换兼容控制台输出
# 状态通过 $env:STS2_SCRIPT_STATUS 传递给 ModManager.ps1 统一显示

$script:BOOTSTRAP_VERSION = "3.0.1"
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$script:UseBasicConsoleOutput = [bool]$env:WT_SESSION

try {
    if (-not $script:UseBasicConsoleOutput) {
        $Host.UI.RawUI.WindowTitle = "皮皮模组管理器"
    }
} catch {
    $script:UseBasicConsoleOutput = $true
}

function Write-Host {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [object[]]$Object,
        [ConsoleColor]$ForegroundColor,
        [ConsoleColor]$BackgroundColor,
        [switch]$NoNewline,
        [object]$Separator
    )

    if (-not $script:UseBasicConsoleOutput) {
        try {
            Microsoft.PowerShell.Utility\Write-Host @PSBoundParameters
            return
        } catch {
            $script:UseBasicConsoleOutput = $true
        }
    }

    $separatorText = if ($PSBoundParameters.ContainsKey("Separator")) { [string]$Separator } else { " " }
    $text = if ($null -eq $Object -or $Object.Count -eq 0) {
        ""
    } else {
        (($Object | ForEach-Object {
            if ($null -eq $_) { return "" }
            return [string]$_
        }) -join $separatorText)
    }

    try {
        if ($NoNewline) {
            [Console]::Write($text)
        } else {
            [Console]::WriteLine($text)
        }
    } catch {
        if ($NoNewline) {
            [Console]::Out.Write($text)
        } else {
            [Console]::Out.WriteLine($text)
        }
    }
}

$API = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("aHR0cHM6Ly8xMzIzOTE5NzQ3LWVjeXh5MzZyYncuYXAtc2hhbmdoYWkudGVuY2VudHNjZi5jb20="))
$LocalScript = [IO.Path]::Combine($PSScriptRoot, "ModManager.ps1")
$TempScript = [IO.Path]::Combine($env:TEMP, "ModManager_latest.ps1")
$DevMode = Test-Path ([IO.Path]::Combine($PSScriptRoot, ".dev"))

function Initialize-ConsoleWindow {
    if ($script:UseBasicConsoleOutput) { return }
    $targetWidth = 220
    $targetHeight = 42

    try {
        $raw = $Host.UI.RawUI
        $maxSize = $raw.MaxPhysicalWindowSize
        if ($maxSize -and $maxSize.Width -gt 0 -and $maxSize.Height -gt 0) {
            $targetWidth = [Math]::Min($targetWidth, $maxSize.Width)
            $targetHeight = [Math]::Min($targetHeight, $maxSize.Height)

            $buffer = $raw.BufferSize
            if ($buffer.Width -lt $targetWidth) { $buffer.Width = $targetWidth }
            if ($buffer.Height -lt 3000) { $buffer.Height = 3000 }
            $raw.BufferSize = $buffer

            $window = $raw.WindowSize
            if ($window.Width -lt $targetWidth) { $window.Width = $targetWidth }
            if ($window.Height -lt $targetHeight) { $window.Height = $targetHeight }
            $raw.WindowSize = $window
        }
    } catch {}

    try {
        if ([Console]::BufferWidth -lt $targetWidth) { [Console]::BufferWidth = $targetWidth }
        if ([Console]::BufferHeight -lt 3000) { [Console]::BufferHeight = 3000 }

        $largestWidth = [Console]::LargestWindowWidth
        $largestHeight = [Console]::LargestWindowHeight
        $windowWidth = [Math]::Min($targetWidth, $largestWidth)
        $windowHeight = [Math]::Min($targetHeight, $largestHeight)
        if ([Console]::WindowWidth -lt $windowWidth -or [Console]::WindowHeight -lt $windowHeight) {
            [Console]::SetWindowSize($windowWidth, $windowHeight)
        }
    } catch {}
}

Initialize-ConsoleWindow

function Initialize-NetworkStack {
    try {
        $protocols = [System.Net.SecurityProtocolType]::Tls12
        try { $protocols = $protocols -bor [System.Net.SecurityProtocolType]::Tls13 } catch {}
        [System.Net.ServicePointManager]::SecurityProtocol = $protocols
    } catch {}

    try { [System.Net.ServicePointManager]::Expect100Continue = $false } catch {}
    try { [System.Net.ServicePointManager]::DefaultConnectionLimit = 8 } catch {}
}

function New-HttpRequest {
    param(
        [string]$Uri,
        [string]$Method = "GET",
        [int]$TimeoutSec = 8
    )

    Initialize-NetworkStack

    $req = [System.Net.HttpWebRequest]::Create($Uri)
    $req.Method = $Method
    $req.Timeout = $TimeoutSec * 1000
    $req.ReadWriteTimeout = $TimeoutSec * 1000
    $req.UserAgent = "STS2ModManager/bootstrap"
    $req.AllowAutoRedirect = $true
    $req.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $req.KeepAlive = $false
    return $req
}

function Get-WebErrorMessage {
    param($ErrorRecord)

    $ex = if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) {
        $ErrorRecord.Exception
    } else {
        $ErrorRecord
    }

    if (-not $ex) { return "未知网络错误" }

    $msg = [string]$ex.Message
    if ($ex.Response -and ($ex.Response -is [System.Net.HttpWebResponse])) {
        try {
            $statusCode = [int]$ex.Response.StatusCode
            $statusText = $ex.Response.StatusDescription
            $msg = "HTTP $statusCode $statusText - $msg"
        } catch {}
    }

    if ($ex.InnerException -and $ex.InnerException.Message) {
        $innerMsg = [string]$ex.InnerException.Message
        if ($innerMsg -and $innerMsg -ne $msg) {
            $msg = "$msg | $innerMsg"
        }
    }

    return $msg
}

function Invoke-JsonGet {
    param([string]$Uri, [int]$TimeoutSec = 8)

    $httpResp = $null
    try {
        $req = New-HttpRequest -Uri $Uri -Method "GET" -TimeoutSec $TimeoutSec
        $httpResp = $req.GetResponse()
        $stream = $httpResp.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
        $json = $reader.ReadToEnd()
        $reader.Close()
        if (-not $json) { return $null }
        return $json | ConvertFrom-Json
    } finally {
        if ($httpResp) { try { $httpResp.Close() } catch {} }
    }
}

function Download-File {
    param(
        [string]$Uri,
        [string]$OutFile,
        [int]$TimeoutSec = 20
    )

    $tempFile = "$OutFile.download"
    $httpResp = $null
    $inputStream = $null
    $outputStream = $null

    try {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        $req = New-HttpRequest -Uri $Uri -Method "GET" -TimeoutSec $TimeoutSec
        $httpResp = $req.GetResponse()
        $inputStream = $httpResp.GetResponseStream()
        $outputStream = [System.IO.File]::Open($tempFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)

        $buffer = New-Object byte[] 65536
        while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outputStream.Write($buffer, 0, $read)
        }
        $outputStream.Flush()
        $outputStream.Close()
        $outputStream = $null
        $inputStream.Close()
        $inputStream = $null
        $httpResp.Close()
        $httpResp = $null

        if (Test-Path $OutFile) {
            Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
        }
        Move-Item $tempFile $OutFile -Force
    } finally {
        if ($outputStream) { try { $outputStream.Close() } catch {} }
        if ($inputStream) { try { $inputStream.Close() } catch {} }
        if ($httpResp) { try { $httpResp.Close() } catch {} }
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

# 读取本地版本号
$localVer = "?"
$localContent = Get-Content $LocalScript -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
if ($localContent) {
    $lm = [regex]::Match($localContent, '\$script:VERSION\s*=\s*"([^"]+)"')
    if ($lm.Success) { $localVer = $lm.Groups[1].Value }
}

$useCloud = $false
$env:STS2_SCRIPT_STATUS = $null
$env:STS2_SCRIPT_DIR = $PSScriptRoot

if ($DevMode) {
    $env:STS2_SCRIPT_STATUS = "dev"
} else {
    try {
        # 传本地版本号，版本一致时服务端返回 {"status":"current"} 跳过下载
        $scriptUri = if ($localVer -ne "?") { "$API/script?v=$localVer" } else { "$API/script" }
        $resp = Invoke-JsonGet -Uri $scriptUri -TimeoutSec 5

        if ($resp.status -eq "current") {
            # 服务端确认版本一致，零下载直接用本地
            $env:STS2_SCRIPT_STATUS = "cached|v$localVer"
        } elseif ($resp.url) {
            Download-File -Uri $resp.url -OutFile $TempScript -TimeoutSec 15
            $file = Get-Item $TempScript
            $size = [math]::Round($file.Length / 1KB, 1)
            $content = Get-Content $TempScript -Raw -Encoding UTF8
            $verMatch = [regex]::Match($content, '\$script:VERSION\s*=\s*"([^"]+)"')
            $cloudVer = if ($verMatch.Success) { $verMatch.Groups[1].Value } else { "?" }

            $cloudIsNewer = $false
            if ($cloudVer -ne "?") {
                if ($localVer -eq "?") {
                    $cloudIsNewer = $true
                } else {
                    try {
                        $cloudIsNewer = ([version]$cloudVer -gt [version]$localVer)
                    } catch {
                        $cloudIsNewer = ($cloudVer -ne $localVer)
                    }
                }
            }

            if ($cloudIsNewer) {
                Write-Host ""
                Write-Host "  发现管理器新版本: v$localVer -> v$cloudVer (${size}KB)" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  按 Y=使用新版本 / Enter=继续用本地版本: " -ForegroundColor White -NoNewline
                $key = Read-Host
                if ($key -eq "Y" -or $key -eq "y") {
                    $useCloud = $true
                    $env:STS2_SCRIPT_STATUS = "update|v$localVer|v$cloudVer|${size}KB"
                } else {
                    $env:STS2_SCRIPT_STATUS = "skip|v$cloudVer"
                }
            } else {
                if ($cloudVer -eq $localVer) {
                    $useCloud = $true
                    $env:STS2_SCRIPT_STATUS = "cloud|v$cloudVer|${size}KB"
                } elseif ($cloudVer -ne "?" -and $localVer -ne "?") {
                    $env:STS2_SCRIPT_STATUS = "localnew|v$localVer|v$cloudVer"
                }
            }
        } else {
            throw "返回数据无效"
        }
    } catch {
        $msg = Get-WebErrorMessage $_
        if ($msg.Length -gt 40) { $msg = $msg.Substring(0, 37) + "..." }
        $env:STS2_SCRIPT_STATUS = "fail|$msg"
    }
}

$scriptToRun = $null
if ($useCloud -and (Test-Path $TempScript)) {
    # 更新本地脚本，下次启动不再重复提示
    try { Copy-Item $TempScript $LocalScript -Force } catch {}
    $scriptToRun = $TempScript
} elseif (Test-Path $LocalScript) {
    $scriptToRun = $LocalScript
}

if ($scriptToRun) {
    try {
        & $scriptToRun
    } catch {
        Write-Host ""
        Write-Host "  [!] 脚本运行出错: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  请截图反馈给 UP 主" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  [!] 未找到 ModManager.ps1，请将压缩包完整解压后再运行" -ForegroundColor Red
    Read-Host "按回车退出"
}
