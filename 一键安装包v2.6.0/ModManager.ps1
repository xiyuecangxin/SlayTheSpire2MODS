# ============================================================
#  杀戮尖塔2 模组管理器 / Slay the Spire 2 Mod Manager
#  Author: 皮一下就很凡@Bilibili
#  https://space.bilibili.com/26786884
#  PowerShell 5.1+ | Windows 10/11
# ============================================================

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$script:UseBasicConsoleOutput = [bool]$env:WT_SESSION

try {
    if (-not $script:UseBasicConsoleOutput) {
        $Host.UI.RawUI.WindowTitle = "杀戮尖塔2 模组管理器"
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

Add-Type -AssemblyName System.Windows.Forms

function Initialize-ConsoleWindow {
    if ($script:UseBasicConsoleOutput) { return }
    try {
        $raw = $Host.UI.RawUI
        $maxSize = $raw.MaxPhysicalWindowSize
        if (-not $maxSize -or $maxSize.Width -le 0 -or $maxSize.Height -le 0) { return }

        $targetWidth = [Math]::Min(220, $maxSize.Width)
        $targetHeight = [Math]::Min(42, $maxSize.Height)

        $buffer = $raw.BufferSize
        if ($buffer.Width -lt $targetWidth) { $buffer.Width = $targetWidth }
        if ($buffer.Height -lt 3000) { $buffer.Height = 3000 }
        $raw.BufferSize = $buffer

        $window = $raw.WindowSize
        if ($window.Width -lt $targetWidth) { $window.Width = $targetWidth }
        if ($window.Height -lt $targetHeight) { $window.Height = $targetHeight }
        $raw.WindowSize = $window
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

# ── 常量 ──
$script:VERSION      = "2.6.0"
$script:STS2_APPID   = "2868840"
$script:STS2_DIRNAME = "Slay the Spire 2"
$script:STS2_EXE     = "SlayTheSpire2.exe"
$script:SCRIPT_DIR   = if ($env:STS2_SCRIPT_DIR) {
    $env:STS2_SCRIPT_DIR
} elseif ($PSScriptRoot -and ($PSScriptRoot -ne $env:TEMP) -and ($PSScriptRoot -ne [IO.Path]::GetTempPath().TrimEnd('\'))) {
    $PSScriptRoot
} else {
    # 云端脚本运行在 TEMP，回退到工作目录（bat 双击时 cwd = bat 所在目录）
    (Get-Location).Path
}
$script:CONFIG_FILE  = [IO.Path]::Combine($SCRIPT_DIR, "modmanager.json")
$script:MODS_SOURCE  = [IO.Path]::Combine($SCRIPT_DIR, "Mods")
$script:SAVE_ROOT    = [IO.Path]::Combine($env:APPDATA, "SlayTheSpire2", "steam")
$script:LOG_DIR      = [IO.Path]::Combine($SCRIPT_DIR, "logs")
$script:MAX_LOGS     = 3
$script:UPDATE_API   = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("aHR0cHM6Ly8xMzIzOTE5NzQ3LWVjeXh5MzZyYncuYXAtc2hhbmdoYWkudGVuY2VudHNjZi5jb20="))
$script:COS_BASE     = "https://sts2-mods-1323919747.cos.ap-shanghai.myqcloud.com"
$script:CACHE_FILE   = [IO.Path]::Combine($SCRIPT_DIR, "update_cache.json")
$script:UPDATE_CACHE_VERSION = 2
$script:CHECK_TTL_HOURS = 12
$script:REPORT_CACHE_FILE = [IO.Path]::Combine($SCRIPT_DIR, "telemetry_cache.json")
$script:REPORT_TTL_HOURS = 12
$script:REPORT_SCHEMA_VERSION = 2
$script:NETWORK_READY = $false
$script:GITEE_CATALOG  = "https://gitee.com/forNoName/sts2-pp-mod-release/raw/master/versions.json"
$script:MOD_TABLE_METADATA = @{
    "DamageMeter" = @{
        ChineseName = "伤害统计"
        Author = "皮一下就很凡"
        CoopAllInstall = $false
    }
    "ModConfig" = @{
        ChineseName = "模组配置"
        Author = "皮一下就很凡"
        CoopAllInstall = $false
    }
    "QuickLink" = @{
        ChineseName = "皮皮快连"
        Author = "皮一下就很凡"
        CoopAllInstall = $true
    }
    "Rewind" = @{
        ChineseName = "皮皮倒带"
        Author = "皮一下就很凡"
        CoopAllInstall = $false
    }
    "SpeedX" = @{
        ChineseName = "皮皮极速"
        Author = "皮一下就很凡"
        CoopAllInstall = $false
    }
    "RemoveMultiplayerPlayerLimit" = @{
        ChineseName = "移除联机人数限制"
        Author = "雨霁Amagari"
        CoopAllInstall = $true
    }
}

# ── 自更新：云端脚本运行在 TEMP，同步回本地目录 ──
if ($MyInvocation.MyCommand.Path -and $script:SCRIPT_DIR) {
    $selfPath = $MyInvocation.MyCommand.Path
    $localCopy = [IO.Path]::Combine($script:SCRIPT_DIR, "ModManager.ps1")
    if ($selfPath -ne $localCopy -and (Test-Path $localCopy)) {
        try { Copy-Item $selfPath $localCopy -Force } catch {}
    }
}

# ── bootstrap 自动升级：将旧版 bootstrap.ps1 升级到 v3.0+ 以节省流量 ──
$script:MIN_BOOTSTRAP_VERSION = "3.0.1"

function Update-BootstrapIfNeeded {
    if (-not $script:SCRIPT_DIR) { return }
    $bootstrapPath = [IO.Path]::Combine($script:SCRIPT_DIR, "bootstrap.ps1")
    if (-not (Test-Path $bootstrapPath)) { return }

    $content = Get-Content $bootstrapPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $content) { return }

    # 检查 bootstrap 版本：有 $script:BOOTSTRAP_VERSION 且 >= 3.0.0 则已是新版
    $match = [regex]::Match($content, '\$script:BOOTSTRAP_VERSION\s*=\s*"([^"]+)"')
    if ($match.Success) {
        try {
            if ([version]$match.Groups[1].Value -ge [version]$script:MIN_BOOTSTRAP_VERSION) { return }
        } catch {}
    }

    # 旧版 bootstrap，从 COS 下载新版覆盖
    try {
        $resp = Invoke-WithRetry -Uri "$($script:UPDATE_API)/script?type=bootstrap" -TimeoutSec 8
        if ($resp.url) {
            $tempBs = "$bootstrapPath.update"
            Download-FileWithRetry -Uri $resp.url -OutFile $tempBs -TimeoutSec 15
            # 验证下载内容包含版本标记
            $newContent = Get-Content $tempBs -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($newContent -and $newContent -match 'BOOTSTRAP_VERSION') {
                # 写回时确保 UTF-8 BOM
                $utf8Bom = New-Object System.Text.UTF8Encoding $true
                [System.IO.File]::WriteAllText($bootstrapPath, $newContent, $utf8Bom)
                Write-Log "bootstrap.ps1 upgraded to v3.0.1+"
            }
            Remove-Item $tempBs -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Log "bootstrap update skipped: $($_.Exception.Message)"
    }
}

# ── 日志管理 ──
function Start-Logging {
    if (-not (Test-Path $script:LOG_DIR)) { New-Item $script:LOG_DIR -ItemType Directory -Force | Out-Null }

    # 清理旧日志，只保留最近 MAX_LOGS - 1 个（为新日志留位置）
    $oldLogs = Get-ChildItem $script:LOG_DIR -Filter "modmanager_*.log" | Sort-Object Name -Descending
    if ($oldLogs.Count -ge $script:MAX_LOGS) {
        $oldLogs | Select-Object -Skip ($script:MAX_LOGS - 1) | Remove-Item -Force
    }

    # 启动 transcript
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:LOG_FILE = Join-Path $script:LOG_DIR "modmanager_$timestamp.log"
    try {
        Start-Transcript -Path $script:LOG_FILE -Append | Out-Null
    } catch {
        # Transcript 可能已在运行（嵌套调用等），忽略
    }
}

function Stop-Logging {
    try { Stop-Transcript | Out-Null } catch {}
}

# ── 配置管理 ──
$script:Config = $null

function Get-DefaultConfig {
    return @{
        GameDir = ""
        TelemetryId = ""
        BetaEntitlements = @{}
        InstalledChannels = @{}
    }
}

function ConvertTo-HashtableDeep($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value.GetType().IsPrimitive -or $Value -is [datetime]) { return $Value }

    if ($Value -is [System.Collections.IDictionary]) {
        $ht = @{}
        foreach ($key in $Value.Keys) {
            $ht[[string]$key] = ConvertTo-HashtableDeep $Value[$key]
        }
        return $ht
    }

    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        $items = @()
        foreach ($item in $Value) {
            $items += ,(ConvertTo-HashtableDeep $item)
        }
        return $items
    }

    $ht = @{}
    $Value.PSObject.Properties | ForEach-Object {
        $ht[$_.Name] = ConvertTo-HashtableDeep $_.Value
    }
    return $ht
}

function Ensure-ConfigDefaults($Config) {
    $defaults = Get-DefaultConfig
    $normalized = @{}

    if ($Config) {
        $Config = ConvertTo-HashtableDeep $Config
    } else {
        $Config = @{}
    }

    foreach ($key in $defaults.Keys) {
        if ($Config.ContainsKey($key)) {
            $normalized[$key] = $Config[$key]
        } else {
            $normalized[$key] = $defaults[$key]
        }
    }

    if (-not ($normalized.BetaEntitlements -is [System.Collections.IDictionary])) {
        $normalized.BetaEntitlements = @{}
    } else {
        $normalized.BetaEntitlements = ConvertTo-HashtableDeep $normalized.BetaEntitlements
    }

    if (-not ($normalized.InstalledChannels -is [System.Collections.IDictionary])) {
        $normalized.InstalledChannels = @{}
    } else {
        $normalized.InstalledChannels = ConvertTo-HashtableDeep $normalized.InstalledChannels
    }

    if (-not $normalized.GameDir) { $normalized.GameDir = "" }
    if (-not $normalized.TelemetryId) { $normalized.TelemetryId = "" }
    return $normalized
}

function Load-Config {
    if (Test-Path $script:CONFIG_FILE) {
        try {
            $raw = Get-Content $script:CONFIG_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
            $script:Config = Ensure-ConfigDefaults $raw
            return
        } catch {}
    }
    $script:Config = Ensure-ConfigDefaults $null
}

function Save-Config {
    $script:Config = Ensure-ConfigDefaults $script:Config
    $script:Config | ConvertTo-Json -Depth 8 | Set-Content $script:CONFIG_FILE -Encoding UTF8
}

function Get-GameDir {
    $dir = $script:Config.GameDir
    if ($dir) {
        try {
            if (Test-Path (Join-Path $dir $script:STS2_EXE)) { return $dir }
        } catch {
            # 驱动器不存在等异常，清除无效配置
            $script:Config.GameDir = ""
            Save-Config
        }
    }
    return $null
}

# ── 输出辅助 ──
function Write-Title($text) {
    Write-Host ""
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host ("  " + ("─" * ($text.Length + 2))) -ForegroundColor DarkGray
    Write-Host ""
}

function Write-Ok($text)   { Write-Host "  [√] $text" -ForegroundColor Green }
function Write-Warn($text) { Write-Host "  [!] $text" -ForegroundColor Yellow }
function Write-Err($text)  { Write-Host "  [!] $text" -ForegroundColor Red }
function Write-Info($text) { Write-Host "  $text" }
function Write-Dim($text)  { Write-Host "  $text" -ForegroundColor DarkGray }

# ── 显示宽度辅助（CJK 字符占 2 列）──
function Get-DisplayWidth($text) {
    $w = 0
    foreach ($c in $text.ToCharArray()) {
        if ([int]$c -gt 0x7F) { $w += 2 } else { $w += 1 }
    }
    return $w
}

function Write-Padded($text, $targetWidth, $color) {
    Write-Host $text -ForegroundColor $color -NoNewline
    $pad = $targetWidth - (Get-DisplayWidth $text)
    if ($pad -gt 0) { Write-Host (" " * $pad) -NoNewline }
}

function Split-ToWidth($text, [int]$maxWidth) {
    $value = if ($text) { [string]$text } else { "-" }
    if ($maxWidth -le 0) { return @($value) }

    $lines = @()
    $remaining = $value
    while ($remaining.Length -gt 0) {
        $chunk = Truncate-ToWidth $remaining $maxWidth
        if (-not $chunk) {
            $chunk = $remaining.Substring(0, 1)
        }
        $lines += @($chunk)
        if ($chunk.Length -ge $remaining.Length) { break }
        $remaining = $remaining.Substring($chunk.Length)
    }

    if ($lines.Count -eq 0) { return @("-") }
    return @($lines)
}

function Write-MenuBoxHeader($title, [int]$contentWidth, $titleColor = "Cyan") {
    $titleText = " $title "
    $lineWidth = $contentWidth + 2 - (Get-DisplayWidth $titleText)
    if ($lineWidth -lt 0) { $lineWidth = 0 }

    Write-Host "  ┌" -ForegroundColor DarkGray -NoNewline
    Write-Host $titleText -ForegroundColor $titleColor -NoNewline
    Write-Host (("─" * $lineWidth) + "┐") -ForegroundColor DarkGray
}

function Write-MenuBoxLine($segments, [int]$contentWidth) {
    Write-Host "  │ " -ForegroundColor DarkGray -NoNewline
    $used = 0
    foreach ($segment in @($segments)) {
        $text = ""
        $color = "Gray"
        if ($segment -is [hashtable]) {
            if ($segment.ContainsKey("Text")) { $text = [string]$segment.Text }
            if ($segment.ContainsKey("Color")) { $color = [string]$segment.Color }
        } else {
            $text = [string]$segment
        }

        Write-Host $text -ForegroundColor $color -NoNewline
        $used += Get-DisplayWidth $text
    }

    $pad = $contentWidth - $used
    if ($pad -lt 0) { $pad = 0 }
    Write-Host ((" " * $pad) + " │") -ForegroundColor DarkGray
}

function Write-MenuBoxFooter([int]$contentWidth) {
    Write-Host ("  └" + ("─" * ($contentWidth + 2)) + "┘") -ForegroundColor DarkGray
}

function Show-MainMenuBanner {
    $contentWidth = 74

    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║   杀戮尖塔2 模组管理器 v$($script:VERSION)              ║" -ForegroundColor Cyan
    Write-Host "  ║   Slay the Spire 2 Mod Manager              ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Cyan

    Write-MenuBoxHeader "公告" $contentWidth "Cyan"
    Write-MenuBoxLine @(
        @{ Text = "作者/B站: "; Color = "DarkGray" },
        @{ Text = "皮一下就很凡@Bilibili"; Color = "White" },
        @{ Text = "  |  主页: "; Color = "DarkGray" },
        @{ Text = "space.bilibili.com/26786884"; Color = "DarkCyan" }
    ) $contentWidth
    Write-MenuBoxLine @(
        @{ Text = "QQ群: "; Color = "DarkGray" },
        @{ Text = "1091537676"; Color = "Cyan" },
        @{ Text = "  |  "; Color = "DarkGray" },
        @{ Text = "有问题可来群里讨论，测试版模组优先发群里"; Color = "Yellow" }
    ) $contentWidth
    Write-MenuBoxLine @(
        @{ Text = "缓存: "; Color = "DarkGray" },
        @{ Text = "启动自动检查有12小时缓存"; Color = "Gray" },
        @{ Text = "  |  "; Color = "DarkGray" },
        @{ Text = "不确定是否最新时运行 6. 检查在线更新"; Color = "Yellow" }
    ) $contentWidth
    Write-MenuBoxLine @(
        @{ Text = "数据站: "; Color = "DarkGray" },
        @{ Text = "http://124.223.63.165/"; Color = "DarkCyan" },
        @{ Text = "  |  "; Color = "DarkGray" },
        @{ Text = "记得更新Skada DPS插件，解锁数据上传功能~"; Color = "Green" }
    ) $contentWidth
    Write-MenuBoxFooter $contentWidth
}

function Get-SlotText($prefix, $slot, $info) {
    if ($info.HasData) {
        $ts = $info.LastModified.ToString("MM-dd HH:mm")
        return "${prefix}${slot}: 有存档  $ts"
    }
    return "${prefix}${slot}: (空)"
}

function Assert-TargetSlotInitialized($dstInfo, $dstLabel, $actionLabel) {
    if ($dstInfo.HasData) { return $true }

    Write-Host ""
    Write-Err "$dstLabel 当前是空槽位，不能直接执行${actionLabel}。"
    Write-Warn "原因：STS2 当前使用 Steam Cloud API，同步时会校验该槽位是否已被游戏正式初始化。"
    Write-Warn "空槽位未初始化时，刚复制进去的 progress.save / prefs.save 可能在启动时被云同步回滚为空。"
    Write-Host ""
    Write-Info "请先这样做："
    Write-Host "    1. 进入游戏，在 $dstLabel 创建一次初始存档" -ForegroundColor White
    Write-Host "    2. 完全退出游戏" -ForegroundColor White
    Write-Host "    3. 再回来执行${actionLabel}覆盖该槽位" -ForegroundColor White
    Write-Host ""
    return $false
}

function Get-InitializedSlotNumbers($infos) {
    $slots = @()
    for ($i = 0; $i -lt $infos.Count; $i++) {
        if ($infos[$i].HasData) {
            $slots += ($i + 1)
        }
    }
    return @($slots)
}

function Get-PreferredTargetSlot($sourceSlot, $targetInfos) {
    if ($sourceSlot -ge 1 -and $sourceSlot -le $targetInfos.Count) {
        if ($targetInfos[$sourceSlot - 1].HasData) {
            return $sourceSlot
        }
    }

    for ($i = 0; $i -lt $targetInfos.Count; $i++) {
        if ($targetInfos[$i].HasData) {
            return ($i + 1)
        }
    }

    return 0
}

function Pause-AndReturn {
    Write-Host ""
    if ($script:UseBasicConsoleOutput) {
        $null = Read-Host "  按回车继续"
        Write-Host ""
        return
    }

    try {
        Write-Host "  按任意键继续..." -ForegroundColor DarkGray -NoNewline
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Write-Host ""
    } catch {
        $script:UseBasicConsoleOutput = $true
        $null = Read-Host "  按回车继续"
        Write-Host ""
    }
}

function Read-Choice($prompt, $validRange) {
    Write-Host ""
    Write-Host "  $prompt" -ForegroundColor White -NoNewline
    $val = Read-Host
    if ($null -eq $val) { return "" }
    return $val.Trim()
}

# ── 自动检测游戏目录 ──
function Find-GameDir {
    # 1. 从注册表获取 Steam 路径
    $steamPath = $null
    foreach ($regPath in @(
        "HKCU:\SOFTWARE\Valve\Steam",
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam"
    )) {
        try {
            $val = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            if ($val.SteamPath) { $steamPath = $val.SteamPath; break }
            if ($val.InstallPath) { $steamPath = $val.InstallPath; break }
        } catch {}
    }

    if ($steamPath) {
        $steamPath = $steamPath -replace '/', '\'

        # 2. 检查 Steam 默认库
        $candidate = Join-Path $steamPath "steamapps\common\$($script:STS2_DIRNAME)"
        if (Test-Path (Join-Path $candidate $script:STS2_EXE)) { return $candidate }

        # 3. 解析 libraryfolders.vdf（包含所有 Steam 库路径）
        $vdfPaths = @(
            (Join-Path $steamPath "steamapps\libraryfolders.vdf"),
            (Join-Path $steamPath "config\libraryfolders.vdf")
        )
        foreach ($vdf in $vdfPaths) {
            if (Test-Path $vdf) {
                $content = Get-Content $vdf -Raw -Encoding UTF8
                $vdfMatches = [regex]::Matches($content, '"path"\s+"([^"]+)"')
                foreach ($m in $vdfMatches) {
                    try {
                        $libPath = $m.Groups[1].Value -replace '\\\\', '\'
                        $candidate = Join-Path $libPath "steamapps\common\$($script:STS2_DIRNAME)"
                        if (Test-Path (Join-Path $candidate $script:STS2_EXE)) { return $candidate }
                    } catch {}  # 驱动器不存在等异常，跳过
                }
                break
            }
        }
    }

    # 4. 暴力搜索常见路径（注册表/vdf 都没找到时的兜底）
    $drives = (Get-PSDrive -PSProvider FileSystem).Root | Where-Object { $_ -match '^[A-Z]:\\$' }
    foreach ($drv in $drives) {
        foreach ($sub in @(
            "SteamLibrary\steamapps\common\$($script:STS2_DIRNAME)",
            "Steam\steamapps\common\$($script:STS2_DIRNAME)",
            "Program Files (x86)\Steam\steamapps\common\$($script:STS2_DIRNAME)",
            "Program Files\Steam\steamapps\common\$($script:STS2_DIRNAME)",
            "Games\Steam\steamapps\common\$($script:STS2_DIRNAME)",
            "Games\SteamLibrary\steamapps\common\$($script:STS2_DIRNAME)",
            "Game\Steam\steamapps\common\$($script:STS2_DIRNAME)",
            "Game\SteamLibrary\steamapps\common\$($script:STS2_DIRNAME)"
        )) {
            try {
                $candidate = Join-Path $drv $sub
                if (Test-Path (Join-Path $candidate $script:STS2_EXE)) { return $candidate }
            } catch {}  # 驱动器不可访问，跳过
        }
    }

    return $null
}

# ── 确保游戏目录可用 ──
function Ensure-GameDir {
    $dir = Get-GameDir
    if ($dir) { return $dir }

    Write-Info "游戏目录未设置或无效，正在自动检测..."
    $dir = Find-GameDir
    if ($dir) {
        Write-Ok "自动检测成功: $dir"
        $script:Config.GameDir = $dir
        Save-Config
        return $dir
    }

    Write-Warn "自动检测失败，请手动指定游戏目录。"
    return Set-GameDirManual
}

function Set-GameDirManual {
    Write-Host ""
    Write-Info "请输入杀戮尖塔2的安装目录（包含 $($script:STS2_EXE) 的文件夹）"
    Write-Dim "例如: D:\SteamLibrary\steamapps\common\Slay the Spire 2"
    Write-Dim "输入 0 返回"
    Write-Host ""
    $path = (Read-Host "  路径").Trim().Trim('"')
    if ($path -eq "0" -or -not $path) { return $null }

    if (Test-Path (Join-Path $path $script:STS2_EXE)) {
        $script:Config.GameDir = $path
        Save-Config
        Write-Ok "游戏目录已设置: $path"
        return $path
    } else {
        Write-Err "未在该目录找到 $($script:STS2_EXE)，请检查路径。"
        return $null
    }
}

# ── 获取 Steam ID ──
function Get-SteamId {
    if (-not (Test-Path $script:SAVE_ROOT)) {
        Write-Err "未找到存档目录: $($script:SAVE_ROOT)"
        Write-Info "请先运行一次游戏以创建存档。"
        return $null
    }

    $ids = @(Get-ChildItem $script:SAVE_ROOT -Directory | Select-Object -ExpandProperty Name)
    if ($ids.Count -eq 0) {
        Write-Err "未找到任何 Steam 用户存档。"
        return $null
    }
    if ($ids.Count -eq 1) { return $ids[0] }

    # 多个用户
    Write-Info "检测到多个 Steam 账号:"
    Write-Host ""
    for ($i = 0; $i -lt $ids.Count; $i++) {
        Write-Info "  $($i+1). $($ids[$i])"
    }
    $choice = Read-Choice "请选择账号 [1-$($ids.Count)]: "
    $idx = [int]$choice - 1
    if ($idx -ge 0 -and $idx -lt $ids.Count) { return $ids[$idx] }
    return $null
}

# ── Steam 云存档缓存同步 ──
# 游戏使用 Steam Cloud 同步存档。手动复制文件后，如果云端时间戳与本地不一致，
# 游戏启动时 SyncCloudToLocal 会用云端（旧）内容覆盖本地（新复制的）文件。
# 解决方案：同时更新 Steam 云缓存目录和 remotecache.vdf，保持一致。

function Get-SteamCloudCachePath($steamId64) {
    # Steam 云缓存: <SteamPath>/userdata/<id32>/<appid>/remote/
    # SteamID32 = SteamID64 低 32 位（等效于 SteamID64 - 76561197960265728）
    $steamPath = $null
    foreach ($regPath in @("HKCU:\SOFTWARE\Valve\Steam", "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam")) {
        try {
            $val = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            if ($val.SteamPath) { $steamPath = $val.SteamPath -replace '/', '\'; break }
            if ($val.InstallPath) { $steamPath = $val.InstallPath -replace '/', '\'; break }
        } catch {}
    }
    if (-not $steamPath) { return $null }

    # SteamID32 (Account ID) = SteamID64 - 76561197960265728
    $id32 = [long]$steamId64 - 76561197960265728

    $cachePath = Join-Path $steamPath "userdata\$id32\$($script:STS2_APPID)"
    if (Test-Path $cachePath) { return $cachePath }
    return $null
}

function Get-ProfileRootPath($steamId, $type, $profileId) {
    if ($type -eq "normal") {
        return Join-Path $script:SAVE_ROOT "$steamId\profile$profileId"
    }
    return Join-Path $script:SAVE_ROOT "$steamId\modded\profile$profileId"
}

function Assert-SaveOperationSafe($actionLabel) {
    $blocking = @()
    foreach ($procName in @([IO.Path]::GetFileNameWithoutExtension($script:STS2_EXE), "steam")) {
        $procs = @(Get-Process -Name $procName -ErrorAction SilentlyContinue)
        foreach ($proc in $procs) {
            if ($blocking -notcontains $proc.ProcessName) {
                $blocking += $proc.ProcessName
            }
        }
    }

    if ($blocking.Count -eq 0) {
        return $true
    }

    Write-Host ""
    Write-Err "检测到以下程序仍在运行: $($blocking -join ', ')"
    Write-Info "为了安全执行${actionLabel}，必须先完全退出游戏和 Steam。"
    Write-Dim "原因：脚本会直接修改本地存档和 Steam 云缓存；如果 Steam 还在运行，内存中的云文件列表可能仍是旧的。"
    Write-Dim "请先退出 SlayTheSpire2.exe 和 Steam.exe（托盘也要退出），然后重新运行这个操作。"
    return $false
}

function Get-ProfileSavesPath($steamId, $type, $profileId) {
    return Join-Path (Get-ProfileRootPath $steamId $type $profileId) "saves"
}

function Get-ProfileReplayPath($steamId, $type, $profileId) {
    return Join-Path (Join-Path (Get-ProfileRootPath $steamId $type $profileId) "replays") "latest.mcr"
}

function Get-ManagedSaveBaseNames {
    return @("progress.save", "prefs.save", "current_run.save", "current_run_mp.save")
}

function Get-ManagedProfileFileMap($profileRoot, [switch]$IncludeBackups, [switch]$IncludeReplay) {
    $fileMap = [ordered]@{}
    $savesPath = Join-Path $profileRoot "saves"
    if (Test-Path $savesPath) {
        foreach ($name in Get-ManagedSaveBaseNames) {
            $filePath = Join-Path $savesPath $name
            if (Test-Path $filePath) {
                $fileMap["saves/$name"] = (Get-Item $filePath).FullName
            }

            if ($IncludeBackups) {
                $backupPath = "$filePath.backup"
                if (Test-Path $backupPath) {
                    $fileMap["saves/$($name).backup"] = (Get-Item $backupPath).FullName
                }
            }
        }

        $historyPath = Join-Path $savesPath "history"
        if (Test-Path $historyPath) {
            $dedupedHistory = @{}
            $historyFiles = Get-ChildItem $historyPath -File -Recurse -Filter "*.run" -ErrorAction SilentlyContinue
            foreach ($f in $historyFiles) {
                if ((-not $dedupedHistory.ContainsKey($f.Name)) -or ($f.LastWriteTimeUtc -gt $dedupedHistory[$f.Name].LastWriteTimeUtc)) {
                    $dedupedHistory[$f.Name] = $f
                }
            }

            foreach ($name in ($dedupedHistory.Keys | Sort-Object)) {
                $fileMap["saves/history/$name"] = $dedupedHistory[$name].FullName
            }
        }
    }

    if ($IncludeReplay) {
        $replayPath = Join-Path (Join-Path $profileRoot "replays") "latest.mcr"
        if (Test-Path $replayPath) {
            $fileMap["replays/latest.mcr"] = (Get-Item $replayPath).FullName
        }
    }

    return $fileMap
}

function Get-LegacyBackupFileMap($backupDir) {
    $fileMap = [ordered]@{}
    foreach ($name in Get-ManagedSaveBaseNames) {
        $primary = Join-Path $backupDir $name
        if (Test-Path $primary) {
            $fileMap["saves/$name"] = (Get-Item $primary).FullName
        }

        $backup = Join-Path $backupDir "$name.backup"
        if (Test-Path $backup) {
            $fileMap["saves/$($name).backup"] = (Get-Item $backup).FullName
        }
    }
    return $fileMap
}

function Reset-ManagedProfileTarget($profileRoot, [switch]$IncludeReplay) {
    $savesPath = Join-Path $profileRoot "saves"
    if (-not (Test-Path $savesPath)) {
        New-Item $savesPath -ItemType Directory -Force | Out-Null
    }

    foreach ($name in Get-ManagedSaveBaseNames) {
        foreach ($suffix in @("", ".backup")) {
            $target = Join-Path $savesPath ($name + $suffix)
            if (Test-Path $target) {
                Remove-Item $target -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Get-ChildItem $savesPath -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*.before_copy*" } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    $historyPath = Join-Path $savesPath "history"
    if (Test-Path $historyPath) {
        Remove-Item $historyPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($IncludeReplay) {
        $replayPath = Join-Path (Join-Path $profileRoot "replays") "latest.mcr"
        if (Test-Path $replayPath) {
            Remove-Item $replayPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Write-ManagedProfileFileMap($fileMap, $dstRoot) {
    $count = 0
    foreach ($entry in $fileMap.GetEnumerator()) {
        $relPath = $entry.Key -replace '/', '\'
        $dstFile = Join-Path $dstRoot $relPath
        $dstDir = Split-Path $dstFile -Parent
        if ($dstDir -and (-not (Test-Path $dstDir))) {
            New-Item $dstDir -ItemType Directory -Force | Out-Null
        }
        Copy-Item $entry.Value $dstFile -Force
        $count++
    }
    return $count
}

function Get-ProfileCopyResult($fileMap, $count) {
    $historyKeys = @($fileMap.Keys | Where-Object { $_ -like "saves/history/*" })
    $backupKeys = @($fileMap.Keys | Where-Object { $_ -like "saves/*.backup" })
    $saveKeys = @($fileMap.Keys | Where-Object {
        ($_ -like "saves/*.save") -and
        ($_ -notlike "saves/history/*") -and
        ($_ -notlike "*.backup")
    })
    return @{
        FileMap      = $fileMap
        Count        = $count
        SaveKeys     = $saveKeys
        BackupKeys   = $backupKeys
        HistoryCount = $historyKeys.Count
        HasReplay    = $fileMap.Contains("replays/latest.mcr")
    }
}

function Copy-ManagedProfileData($srcRoot, $dstRoot, [switch]$IncludeBackups, [switch]$IncludeReplay) {
    $fileMap = Get-ManagedProfileFileMap $srcRoot -IncludeBackups:$IncludeBackups -IncludeReplay:$IncludeReplay
    Reset-ManagedProfileTarget $dstRoot -IncludeReplay:$IncludeReplay
    $count = Write-ManagedProfileFileMap $fileMap $dstRoot
    return Get-ProfileCopyResult $fileMap $count
}

function Remove-RemoteCacheVdfEntries($vdfPath, $exactKeys, $prefixKeys) {
    if (-not (Test-Path $vdfPath)) { return }

    $content = Get-Content $vdfPath -Raw -Encoding UTF8

    foreach ($key in ($exactKeys | Where-Object { $_ } | Sort-Object -Unique)) {
        $pattern = '(?ms)^\s*"' + [regex]::Escape($key) + '"\s*\{.*?^\s*\}\s*'
        $content = [regex]::Replace($content, $pattern, "")
    }

    foreach ($prefix in ($prefixKeys | Where-Object { $_ } | Sort-Object -Unique)) {
        $pattern = '(?ms)^\s*"' + [regex]::Escape($prefix) + '[^"]*"\s*\{.*?^\s*\}\s*'
        $content = [regex]::Replace($content, $pattern, "")
    }

    [IO.File]::WriteAllText($vdfPath, $content, [Text.Encoding]::UTF8)
}

function Get-RemoteCacheVdfKeys($vdfPath, $prefix) {
    if (-not (Test-Path $vdfPath)) { return @() }

    $content = Get-Content $vdfPath -Raw -Encoding UTF8
    return @([regex]::Matches($content, '(?m)^\s*"([^"]+)"\s*\{') |
        ForEach-Object { $_.Groups[1].Value } |
        Where-Object { $_ -like "$prefix*" })
}

function New-RemoteCacheVdfEntryBlock($vdfKey, $size, $sha1, $nowUnix) {
    return @"
	"$vdfKey"
	{
		"root"		"0"
		"size"		"$size"
		"localtime"		"$nowUnix"
		"time"		"$nowUnix"
		"remotetime"		"0"
		"sha"		"$sha1"
		"syncstate"		"3"
		"persiststate"		"0"
		"platformstosync2"		"-1"
	}
"@
}

function Sync-SteamCloudCache($steamId64, $dstType, $dstSlot) {
    # 将已复制的正式存档同步到 Steam 云缓存，防止云同步覆盖。
    # 与游戏源码保持一致：仅同步 progress/prefs/current_run/current_run_mp/history/*.run。
    $cachePath = Get-SteamCloudCachePath $steamId64
    if (-not $cachePath) {
        Write-Warn "未找到 Steam 云缓存目录，跳过云同步。"
        Write-Warn "如果存档被覆盖，请在游戏运行时（切到其他存档槽位后）重新复制。"
        return $false
    }

    $remotePath = Join-Path $cachePath "remote"
    $vdfPath = Join-Path $cachePath "remotecache.vdf"
    if (-not (Test-Path $remotePath)) {
        Write-Warn "Steam 云缓存 remote 目录不存在，跳过。"
        return $false
    }

    $localProfileRoot = Get-ProfileRootPath $steamId64 $dstType $dstSlot
    $localFileMap = Get-ManagedProfileFileMap $localProfileRoot

    $cloudRelRoot = if ($dstType -eq "normal") {
        "profile$dstSlot"
    } else {
        "modded\profile$dstSlot"
    }
    $cloudProfileRoot = Join-Path $remotePath $cloudRelRoot
    if (-not (Test-Path $cloudProfileRoot)) {
        New-Item $cloudProfileRoot -ItemType Directory -Force | Out-Null
    }

    $cloudCurrentMap = Get-ManagedProfileFileMap $cloudProfileRoot -IncludeBackups
    $cloudRelRootVdf = $cloudRelRoot -replace '\\', '/'
    $desiredVdfKeys = @($localFileMap.Keys | ForEach-Object { "$cloudRelRootVdf/$($_)" })
    $removeExactKeys = @($cloudCurrentMap.Keys | Where-Object {
        $desiredKey = "$cloudRelRootVdf/$($_)"
        $desiredVdfKeys -notcontains $desiredKey
    } | ForEach-Object { "$cloudRelRootVdf/$($_)" })
    if (Test-Path $vdfPath) {
        $allProfileVdfKeys = Get-RemoteCacheVdfKeys $vdfPath "$cloudRelRootVdf/"
        $removeExactKeys += @($allProfileVdfKeys | Where-Object {
            $desiredVdfKeys -notcontains $_
        })
    }

    $cloudSavesPath = Join-Path $cloudProfileRoot "saves"
    if (Test-Path $cloudSavesPath) {
        $beforeCopyKeys = Get-ChildItem $cloudSavesPath -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*.before_copy*" } |
            ForEach-Object { "$cloudRelRootVdf/saves/$($_.Name)" }
        $removeExactKeys += @($beforeCopyKeys)
    }

    Reset-ManagedProfileTarget $cloudProfileRoot
    $cloudUpdated = Write-ManagedProfileFileMap $localFileMap $cloudProfileRoot

    if (Test-Path $vdfPath) {
        try {
            Update-RemoteCacheVdf $vdfPath $cloudRelRoot $cloudProfileRoot
            Remove-RemoteCacheVdfEntries $vdfPath $removeExactKeys @("$cloudRelRootVdf/saves/history/history/")
            $verifiedKeys = Get-RemoteCacheVdfKeys $vdfPath "$cloudRelRootVdf/"
            $missingDesiredKeys = @($desiredVdfKeys | Where-Object { $verifiedKeys -notcontains $_ })
            if ($missingDesiredKeys.Count -gt 0) {
                throw "remotecache.vdf 缺少 $($missingDesiredKeys.Count) 个目标条目（例如: $($missingDesiredKeys[0])）"
            }
        } catch {
            Write-Dim "  remotecache.vdf 更新失败: $($_.Exception.Message)"
            Write-Dim "  为防止 Steam 云同步删除刚复制的空槽位存档，请先不要启动游戏。"
            return $false
        }
    }

    foreach ($entry in $localFileMap.GetEnumerator()) {
        $relPath = $entry.Key -replace '/', '\'
        $cloudFile = Join-Path $cloudProfileRoot $relPath
        if ((Test-Path $cloudFile) -and (Test-Path $entry.Value)) {
            $ts = (Get-Item $cloudFile).LastWriteTimeUtc
            (Get-Item $entry.Value).LastWriteTimeUtc = $ts
        }
    }

    Write-Ok "Steam 云缓存已同步（$cloudUpdated 个正式文件），存档不会被云端覆盖。"
    return $true
}

function Update-RemoteCacheVdf($vdfPath, $relBase, $cloudDstDir) {
    # 更新或创建 remotecache.vdf 条目。
    # VDF 格式：每个文件条目以 "path/file" { ... } 结构存储
    # 兼容 PowerShell 5.1（不使用 ScriptBlock 替换）
    $content = Get-Content $vdfPath -Raw -Encoding UTF8
    $nowUnix = [long]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())

    # 遍历目标目录的文件，更新对应 VDF 条目
    $files = Get-ChildItem $cloudDstDir -File -Recurse -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        $relFile = $f.FullName.Substring($cloudDstDir.Length).TrimStart('\', '/') -replace '\\', '/'
        # VDF 中的 key 使用 / 分隔符，如 "profile1/saves/progress.save"
        $vdfKey = ($relBase -replace '\\', '/') + "/" + $relFile

        # 计算 SHA1
        $sha1 = (Get-FileHash $f.FullName -Algorithm SHA1).Hash.ToLower()
        $size = $f.Length

        # 查找 VDF 条目块并逐字段替换（PS 5.1 兼容）
        $escapedKey = [regex]::Escape($vdfKey)
        $blockPattern = "(?s)(`"$escapedKey`"\s*\{)(.*?)(\})"
        $blockMatch = [regex]::Match($content, $blockPattern)
        if ($blockMatch.Success) {
            $block = $blockMatch.Groups[2].Value
            $block = $block -replace '("size"\s+")[^"]*"', "`${1}$size`""
            $block = $block -replace '("localtime"\s+")[^"]*"', "`${1}$nowUnix`""
            $block = $block -replace '("time"\s+")[^"]*"', "`${1}$nowUnix`""
            $block = $block -replace '("sha"\s+")[^"]*"', "`${1}$sha1`""
            $block = $block -replace '("syncstate"\s+")[^"]*"', "`${1}4`""
            $newBlock = $blockMatch.Groups[1].Value + $block + $blockMatch.Groups[3].Value
            $content = $content.Remove($blockMatch.Index, $blockMatch.Length).Insert($blockMatch.Index, $newBlock)
        } else {
            $newBlock = New-RemoteCacheVdfEntryBlock $vdfKey $size $sha1 $nowUnix
            $insertIndex = $content.LastIndexOf("}")
            if ($insertIndex -lt 0) {
                throw "无法在 remotecache.vdf 中找到根闭合括号"
            }
            $content = $content.Insert($insertIndex, $newBlock + "`r`n")
        }
    }

    [IO.File]::WriteAllText($vdfPath, $content, [Text.Encoding]::UTF8)
}

# ── 获取存档槽位信息 ──
function Get-ProfileInfo($steamId, $type, $profileId) {
    $base = Get-ProfileSavesPath $steamId $type $profileId
    $progressFile = Join-Path $base "progress.save"
    $hasData = Test-Path $progressFile
    $lastModified = $null
    if ($hasData) {
        $lastModified = (Get-Item $progressFile).LastWriteTime
    }
    return @{
        Path         = $base
        HasData      = $hasData
        LastModified = $lastModified
        ProfileId    = $profileId
    }
}

# ── 扫描可安装模组（分发包中的） ──
function Get-AvailableMods {
    if (-not (Test-Path $script:MODS_SOURCE)) { return @() }
    $selected = @{}
    foreach ($dir in (Get-ChildItem $script:MODS_SOURCE -Directory -ErrorAction SilentlyContinue)) {
        try {
            $installName = Get-InstallName $dir.FullName
            if (-not $installName) { continue }

            $manifest = Get-PreferredModManifest $dir.FullName
            $version = if ($manifest -and $manifest.version) { [string]$manifest.version } else { "" }

            if (-not $selected.ContainsKey($installName)) {
                $selected[$installName] = @{
                    Dir = $dir
                    Version = $version
                }
                continue
            }

            $current = $selected[$installName]
            $cmp = Compare-VersionValue $version ([string]$current.Version)
            if ($cmp -gt 0) {
                $selected[$installName] = @{
                    Dir = $dir
                    Version = $version
                }
                continue
            }

            if ($cmp -eq 0) {
                if (($dir.Name -eq $installName) -and ($current.Dir.Name -ne $installName)) {
                    $selected[$installName] = @{
                        Dir = $dir
                        Version = $version
                    }
                }
            }
        } catch {}
    }
    return @($selected.GetEnumerator() | Sort-Object Name | ForEach-Object { $_.Value.Dir })
}

# ── 扫描已安装模组 ──
function Read-ModernManifestFile($manifestPath) {
    if (-not $manifestPath -or -not (Test-Path $manifestPath)) { return $null }
    try {
        $obj = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($obj -and $obj.id -and $obj.version) { return $obj }
    } catch {}
    return $null
}

function Get-LooseModFiles($modsDir, [string]$modId) {
    if (-not $modsDir -or -not $modId) { return @() }
    $files = @()
    foreach ($ext in @("json", "dll", "pck")) {
        $path = Join-Path $modsDir ("{0}.{1}" -f $modId, $ext)
        if (Test-Path $path) {
            $item = Get-Item $path -ErrorAction SilentlyContinue
            if ($item -and -not $item.PSIsContainer) {
                $files += @($item)
            }
        }
    }
    return @($files)
}

function Get-InstalledModFiles($mod) {
    if (-not $mod) { return @() }
    if ($mod.IsLoose) {
        return @(Get-LooseModFiles $mod.ModsDir $mod.Name)
    }
    return @(Get-ChildItem $mod.FullName -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "*.bak*" })
}

function Get-InstalledModLabel($mod) {
    if (-not $mod) { return "" }
    $manifest = $mod.Manifest
    $name = [string]$mod.Name
    $label = $name
    if ($manifest -and $manifest.name -and $manifest.name -ne $name) {
        $label = "$($manifest.name) ($name)"
    }
    $ver = if ($manifest -and $manifest.version) { [string]$manifest.version } else { "?" }
    $label += " v$ver"
    if ($manifest -and $manifest.author) {
        $label += " by $($manifest.author)"
    }
    $layoutTag = if ($mod.IsLoose) { "[Loose]" } else { "[目录]" }
    return "$label $layoutTag"
}

function Format-FileSizeText($totalBytes) {
    if (-not $totalBytes) { $totalBytes = 0 }
    if ($totalBytes -gt 1MB) { return "{0:N1} MB" -f ($totalBytes / 1MB) }
    if ($totalBytes -gt 1KB) { return "{0:N0} KB" -f ($totalBytes / 1KB) }
    return "$totalBytes B"
}

function Remove-LooseModFiles($modsDir, [string]$modId, [string]$ActionLabel) {
    $files = @(Get-LooseModFiles $modsDir $modId)
    if ($files.Count -eq 0) { return $true }

    if ($ActionLabel) {
        Write-Dim "    检测到根目录 loose 文件，正在$ActionLabel..."
    }

    $failed = $false
    foreach ($file in $files) {
        try {
            Remove-Item $file.FullName -Force -ErrorAction Stop
        } catch {
            Write-Host "    [!] 无法删除 $($file.Name)（文件被锁定，请关闭游戏后重试）" -ForegroundColor Red
            $failed = $true
        }
    }

    if ($failed) {
        $remaining = @(Get-LooseModFiles $modsDir $modId)
        if ($remaining.Count -gt 0) { return $false }
    }

    return $true
}

function Remove-LegacyExternalManifest([string]$modDir, [string]$ActionLabel) {
    if (-not $modDir) { return $true }

    $legacyPath = Join-Path $modDir "mod_manifest.json"
    if (-not (Test-Path $legacyPath)) { return $true }

    try {
        Remove-Item $legacyPath -Force -ErrorAction Stop
        Write-Dim "    已清理旧的 mod_manifest.json"
        return $true
    } catch {
        Write-Host "    [!] $ActionLabel 失败: mod_manifest.json 被占用，请关闭游戏后重试" -ForegroundColor Red
        return $false
    }
}

function Copy-InstalledModContent($mod, $destDir) {
    if ($mod.IsLoose) {
        foreach ($file in (Get-InstalledModFiles $mod)) {
            Copy-Item $file.FullName (Join-Path $destDir $file.Name) -Force
        }
        return
    }
    Copy-Item "$($mod.FullName)\*" -Destination $destDir -Force -Recurse
}

function Get-InstalledMods($gameDir) {
    $modsDir = Join-Path $gameDir "mods"
    if (-not (Test-Path $modsDir)) { return @() }

    $mods = @{}
    $directoryIndex = @{}

    foreach ($dir in (Get-ChildItem $modsDir -Directory -ErrorAction SilentlyContinue)) {
        try {
            $installName = Get-InstallName $dir.FullName
            if (-not $installName) { continue }

            $entry = [pscustomobject]@{
                Name = $installName
                FullName = $dir.FullName
                ModsDir = $modsDir
                InstallDir = $dir.FullName
                Manifest = Get-PreferredModManifest $dir.FullName
                IsLoose = $false
                HasLooseDuplicate = $false
                LooseFiles = @()
            }

            if (-not $mods.ContainsKey($installName)) {
                $mods[$installName] = $entry
            }

            $directoryIndex[[string]$installName] = $mods[$installName]
            $directoryIndex[[string]$dir.Name] = $mods[$installName]
        } catch {}
    }

    $jsonFiles = @(Get-ChildItem $modsDir -Filter "*.json" -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -ine "mod_manifest.json"
    })
    foreach ($file in $jsonFiles) {
        $manifest = Read-ModernManifestFile $file.FullName
        if (-not $manifest -or -not $manifest.id) { continue }

        $modId = [string]$manifest.id
        $looseFiles = @(Get-LooseModFiles $modsDir $modId)
        if ($directoryIndex.ContainsKey($modId)) {
            $dirEntry = $directoryIndex[$modId]
            $dirEntry.HasLooseDuplicate = $true
            $dirEntry.LooseFiles = $looseFiles
            continue
        }
        if ($mods.ContainsKey($modId)) { continue }

        $mods[$modId] = [pscustomobject]@{
            Name = $modId
            FullName = $file.FullName
            ModsDir = $modsDir
            InstallDir = (Join-Path $modsDir $modId)
            Manifest = $manifest
            IsLoose = $true
            HasLooseDuplicate = $false
            LooseFiles = $looseFiles
        }
    }

    return @($mods.GetEnumerator() | Sort-Object Name | ForEach-Object { $_.Value })
}

# ── 读取 legacy mod_manifest.json（仅 fallback） ──
function Get-ModManifest($modDir) {
    $manifestPath = Join-Path $modDir "mod_manifest.json"
    if (Test-Path $manifestPath) {
        try {
            return Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch { return $null }
    }
    return $null
}

# ── 读取 v0.99+ 根 manifest（<ModId>.json） ──
function Get-ModernModManifest($modDir) {
    $jsonFiles = Get-ChildItem $modDir -Filter "*.json" -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -ine "mod_manifest.json"
    }
    foreach ($file in $jsonFiles) {
        $obj = Read-ModernManifestFile $file.FullName
        if ($obj) { return $obj }
    }
    return $null
}

function Get-PreferredModManifest($modDir) {
    $manifest = Get-ModernModManifest $modDir
    if (-not $manifest) { $manifest = Get-ModManifest $modDir }
    return $manifest
}

# ── 推断安装目录名 ──
# 优先级: modern manifest.id > legacy manifest.pck_name > DLL/PCK 文件名 > 文件夹名
function Get-InstallName($modDir) {
    $manifest = Get-ModernModManifest $modDir
    if ($manifest -and $manifest.id) { return $manifest.id }
    $manifest = Get-ModManifest $modDir
    if ($manifest -and $manifest.pck_name) { return $manifest.pck_name }
    # 没有 manifest 或没有 pck_name — 从 DLL 文件名推断
    $dll = Get-ChildItem $modDir -Filter "*.dll" -File | Where-Object { $_.Name -notlike "*.bak*" } | Select-Object -First 1
    if ($dll) { return $dll.BaseName }
    # 最后用文件夹名
    return (Split-Path $modDir -Leaf)
}

# ── 格式化模组显示名 ──
function Format-ModLabel($modDir) {
    $manifest = Get-PreferredModManifest $modDir
    $dirName = Split-Path $modDir -Leaf
    if ($manifest) {
        $label = $dirName
        if ($manifest.name -and $manifest.name -ne $dirName) {
            $label = "$($manifest.name) ($dirName)"
        }
        $ver = if ($manifest.version) { $manifest.version } else { "unknown" }
        $label += " v$ver"
        if ($manifest.author) { $label += " by $($manifest.author)" }
        return $label
    }
    # 无 manifest — 尝试从文件名推断
    $installName = Get-InstallName $modDir
    if ($installName -ne $dirName) {
        return "$installName ($dirName) v?"
    }
    return "$dirName v?"
}

function New-MenuEntry {
    param(
        [string]$Name,
        [string]$Version,
        [string]$Channel = "stable",
        [string]$InstalledChannel = "stable",
        [string]$InstalledVersion = "",
        [string]$ActionKind,
        [string]$Notice
    )

    $entry = @{
        Name = $Name
        LocalName = $Name
        CloudName = $Name
        LocalVer = $InstalledVersion
        RemoteVer = $Version
        InstallDir = ""
        TargetChannel = $Channel
        InstalledChannel = $InstalledChannel
        ActionKind = $ActionKind
        HasLocal = [bool]$InstalledVersion
        StatusTag = ""
        Notice = $Notice
        Token = ""
        Changelog = ""
        ChangelogDetail = $null
        UpdatedAt = ""
        Filename = ""
    }
    return Apply-EntryMetadata -Entry $entry
}

function Get-InstallMenuRemoteEntries {
    param([string]$gameDir)

    $hasEntitlements = ((Get-BetaEntitlementsMap).Keys | Measure-Object).Count -gt 0
    if (-not $hasEntitlements) { return @() }

    $checkResult = $script:LastCheckResult
    if (-not $checkResult) {
        try {
            $checkResult = Refresh-UpdateState -gameDir $gameDir -UseCache $true
        } catch {
            $checkResult = $null
        }
    }
    if (-not $checkResult -or $checkResult.Error) { return @() }

    $rows = @()
    foreach ($item in @($checkResult.Updates) + @($checkResult.UpToDate)) {
        $targetChannel = if ($item.TargetChannel) { [string]$item.TargetChannel } else { "" }
        $installedChannel = if ($item.InstalledChannel) { [string]$item.InstalledChannel } else { "" }
        if (($targetChannel -ne "beta") -and ($installedChannel -ne "beta")) { continue }

        if ([string]$item.ActionKind -eq "current") {
            $entry = New-MenuEntry `
                -Name ([string]$item.Name) `
                -Version ([string]$item.RemoteVer) `
                -Channel $(if ($targetChannel) { $targetChannel } else { $installedChannel }) `
                -InstalledChannel $(if ($installedChannel) { $installedChannel } else { "stable" }) `
                -InstalledVersion ([string]$item.LocalVer) `
                -ActionKind "menu_install_remote_current" `
                -Notice $(if ($installedChannel -eq "beta") { "【已安装】当前测试版已是最新" } else { "【已安装】当前版本已是最新" })
        } else {
            $entry = Apply-EntryMetadata -Entry $item
        }
        $rows += $entry
    }

    $deduped = @{}
    foreach ($row in ($rows | Sort-Object Name)) {
        $deduped[[string]$row.Name] = $row
    }
    return @($deduped.GetEnumerator() | Sort-Object Name | ForEach-Object { $_.Value })
}

function Get-InstallableMenuCount {
    param([string]$gameDir)

    $names = @{}
    foreach ($mod in @(Get-AvailableMods)) {
        try {
            $installName = Get-InstallName $mod.FullName
            if ($installName) { $names[$installName] = $true }
        } catch {}
    }
    foreach ($entry in @(Get-InstallMenuRemoteEntries -gameDir $gameDir)) {
        if ([string]$entry.ActionKind -eq "menu_install_remote_current") { continue }
        if ($entry -and $entry.Name) { $names[[string]$entry.Name] = $true }
    }
    return $names.Count
}

function Get-ModTelemetryRecord($modDir) {
    $modern = Get-ModernModManifest $modDir
    if ($modern -and $modern.id) {
        return [pscustomobject]@{
            Id      = [string]$modern.id
            Version = if ($modern.version) { [string]$modern.version } else { "unknown" }
            Name    = if ($modern.name) { [string]$modern.name } else { [string]$modern.id }
        }
    }

    $legacy = Get-ModManifest $modDir
    if ($legacy) {
        $legacyId = if ($legacy.pck_name) { [string]$legacy.pck_name } else { [string](Get-InstallName $modDir) }
        return [pscustomobject]@{
            Id      = $legacyId
            Version = if ($legacy.version) { [string]$legacy.version } else { "unknown" }
            Name    = if ($legacy.name) { [string]$legacy.name } else { $legacyId }
        }
    }

    $fallbackId = [string](Get-InstallName $modDir)
    if (-not $fallbackId) { return $null }
    return [pscustomobject]@{
        Id      = $fallbackId
        Version = "unknown"
        Name    = $fallbackId
    }
}

function Get-InstalledModTelemetry($gameDir) {
    $records = @{}
    foreach ($modDir in (Get-InstalledMods $gameDir)) {
        try {
            $record = Get-ModTelemetryRecord $modDir.FullName
            if (-not $record -or -not $record.Id) { continue }
            if ($records.ContainsKey($record.Id)) {
                $existing = $records[$record.Id]
                if (($existing.Version -eq "unknown") -and ($record.Version -ne "unknown")) {
                    $records[$record.Id] = $record
                }
                continue
            }
            $records[$record.Id] = $record
        } catch {}
    }
    return @($records.GetEnumerator() | Sort-Object Name | ForEach-Object { $_.Value })
}

# ============================================================
#  功能: 安装模组
# ============================================================
function Install-Mod {
    $gameDir = Ensure-GameDir
    if (-not $gameDir) {
        Write-Err "无法确定游戏目录，安装中止。"
        Pause-AndReturn
        return
    }

    Write-Title "安装模组"

    $mods = @(Get-AvailableMods | Sort-Object Name)
    $installedStates = Get-InstalledModStates $gameDir
    $remoteEntries = @(Get-InstallMenuRemoteEntries -gameDir $gameDir)

    if ($mods.Count -eq 0 -and $remoteEntries.Count -eq 0) {
        Write-Warn "未找到可安装的模组。"
        Write-Info "请确保 Mods 文件夹与本脚本在同一目录下；测试版模组可先录入测试码后再查看。"
        Pause-AndReturn
        return
    }

    Write-Info "可用模组:"
    Write-Host ""

    $installOptions = @()
    $remoteByName = @{}
    foreach ($entry in $remoteEntries) {
        $remoteByName[[string]$entry.Name] = $entry
    }

    for ($i = 0; $i -lt $mods.Count; $i++) {
        $srcManifest = Get-PreferredModManifest $mods[$i].FullName
        $installName = Get-InstallName $mods[$i].FullName

        if ($remoteByName.ContainsKey($installName)) {
            $remoteEntry = $remoteByName[$installName]
            $installOptions += @(@{
                Kind = "remote"
                Entry = $remoteEntry
                UpdateItem = $remoteEntry
                ModDir = $null
                CanExecute = ([string]$remoteEntry.ActionKind -ne "menu_install_remote_current")
            })
            $remoteByName.Remove($installName)
            continue
        }

        $srcVer = if ($srcManifest -and $srcManifest.version) { [string]$srcManifest.version } else { "" }

        if ($installedStates.ContainsKey($installName)) {
            $installed = $installedStates[$installName]
            $instVer = [string]$installed.LocalVer
            $instChannel = [string]$installed.Channel

            if ($instChannel -eq "beta") {
                $row = New-MenuEntry -Name $installName -Version $srcVer -Channel "stable" -InstalledChannel "beta" -InstalledVersion $instVer -ActionKind "menu_install_beta" -Notice "【测试已装】当前本地为测试版；离线安装会切回正式版"
            } else {
                $cmp = if ($srcVer -and $instVer) { Compare-VersionValue $srcVer $instVer } else { 0 }
                if ($cmp -gt 0) {
                    $row = New-MenuEntry -Name $installName -Version $srcVer -Channel "stable" -InstalledChannel "stable" -InstalledVersion $instVer -ActionKind "menu_install_update" -Notice "【可更新】离线包较新，可覆盖安装"
                } elseif ($cmp -lt 0) {
                    $row = New-MenuEntry -Name $installName -Version $srcVer -Channel "stable" -InstalledChannel "stable" -InstalledVersion $instVer -ActionKind "menu_install_older" -Notice "【较旧包】离线包旧于当前安装，继续会降级"
                } else {
                    $row = New-MenuEntry -Name $installName -Version $srcVer -Channel "stable" -InstalledChannel "stable" -InstalledVersion $instVer -ActionKind "menu_install_current" -Notice "【已安装】当前已是该离线版本"
                }
            }
        } else {
            $row = New-MenuEntry -Name $installName -Version $srcVer -Channel "stable" -ActionKind "menu_install" -Notice "【可安装】离线稳定版"
        }

        $installOptions += @(@{
            Kind = "local"
            Entry = $row
            ModDir = $mods[$i]
            CanExecute = ([string]$row.ActionKind -ne "menu_install_current")
        })
    }

    foreach ($entry in ($remoteByName.GetEnumerator() | Sort-Object Name | ForEach-Object { $_.Value })) {
        $installOptions += @(@{
            Kind = "remote"
            Entry = $entry
            UpdateItem = $entry
            ModDir = $null
            CanExecute = ([string]$entry.ActionKind -ne "menu_install_remote_current")
        })
    }

    $installRows = @($installOptions | ForEach-Object { $_.Entry })
    $widths = Get-UpdateTableWidths -Rows $installRows
    Write-UpdateTableHeader -Widths $widths
    for ($i = 0; $i -lt $installOptions.Count; $i++) {
        $row = $installOptions[$i].Entry
        $isDim = (-not [bool]$installOptions[$i].CanExecute)
        Write-UpdateTableRow -Prefix "$($i + 1)." -PrefixColor $(if ($isDim) { "DarkGray" } else { "Yellow" }) -Entry $row -IsCurrent $isDim -Widths $widths
    }

    $allLabel = if ($remoteEntries.Count -gt 0) { "    A. 安装全部（含测试）" } else { "    A. 安装全部" }
    Write-Host $allLabel -ForegroundColor Cyan
    Write-Host "    0. 返回主菜单" -ForegroundColor DarkGray
    $choice = Read-Choice "请选择要安装的模组 [编号/A/0]: "

    if ($choice -eq "0") { return }

    $selectedOptions = @()
    if ($choice -ieq "A") {
        $preferredByName = @{}
        foreach ($option in $installOptions) {
            $key = [string]$option.Entry.Name
            if ($option.Kind -eq "remote") {
                $preferredByName[$key] = $option
            } elseif (-not $preferredByName.ContainsKey($key)) {
                $preferredByName[$key] = $option
            }
        }
        foreach ($option in $installOptions) {
            $key = [string]$option.Entry.Name
            if ($preferredByName.ContainsKey($key) -and ($preferredByName[$key] -eq $option)) {
                if ([bool]$option.CanExecute) {
                    $selectedOptions += @($option)
                }
                $preferredByName.Remove($key)
            }
        }
    } else {
        $parts = $choice -replace '，', ',' -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        $invalid = $false
        foreach ($p in $parts) {
            $idx = 0
            if (-not [int]::TryParse($p, [ref]$idx)) { $invalid = $true; break }
            $idx = $idx - 1
            if ($idx -lt 0 -or $idx -ge $installOptions.Count) { $invalid = $true; break }
            $selectedOptions += @($installOptions[$idx])
        }
        if ($invalid -or $selectedOptions.Count -eq 0) {
            Write-Err "无效选择。"
            Pause-AndReturn
            return
        }
    }

    if ($selectedOptions.Count -eq 0) {
        Write-Info "所选模组当前都已是最新，无需安装。"
        Pause-AndReturn
        return
    }

    $destRoot = Join-Path $gameDir "mods"
    if (-not (Test-Path $destRoot)) { New-Item $destRoot -ItemType Directory -Force | Out-Null }

    foreach ($option in $selectedOptions) {
        if (-not [bool]$option.CanExecute) {
            Write-Host ""
            Write-Dim "[$($option.Entry.Name)] 当前已是最新，无需重复安装。"
            continue
        }
        if ($option.Kind -eq "remote") {
            Write-Host ""
            $null = Update-SingleMod $option.UpdateItem
            continue
        }

        $mod = $option.ModDir
        Write-Host ""
        $installName = Get-InstallName $mod.FullName
        $displayName = Format-ModLabel $mod.FullName

        Write-Info "正在安装: $displayName ..."
        if ($installName -ne $mod.Name) {
            Write-Dim "  安装目录: $installName"
        }
        if (-not (Remove-LooseModFiles $destRoot $installName "清理旧的 loose 布局")) {
            Write-Warn "$displayName 安装已取消，请关闭游戏后重试。"
            continue
        }
        $destDir = Join-Path $destRoot $installName
        if (-not (Test-Path $destDir)) { New-Item $destDir -ItemType Directory -Force | Out-Null }
        if (-not (Remove-LegacyExternalManifest $destDir "清理旧的 legacy manifest")) {
            Write-Warn "$displayName 安装已取消，请关闭游戏后重试。"
            continue
        }

        $files = Get-ChildItem $mod.FullName -File
        $copyFailed = $false
        foreach ($f in $files) {
            $destFile = Join-Path $destDir $f.Name
            try {
                Copy-Item $f.FullName $destFile -Force
                Write-Host "    [√] $($f.Name)" -ForegroundColor Green
            } catch {
                $bakName = "$($f.Name).bak.$(Get-Random)"
                try {
                    Rename-Item $destFile $bakName -Force -ErrorAction Stop
                    Copy-Item $f.FullName $destFile -Force
                    Write-Host "    [√] $($f.Name) (已替换锁定文件)" -ForegroundColor Green
                } catch {
                    Write-Host "    [!] 无法复制 $($f.Name)（文件被锁定，请关闭游戏后重试）" -ForegroundColor Red
                    $copyFailed = $true
                }
            }
        }
        if (-not $copyFailed) {
            Set-InstalledChannel -ModName $installName -Channel "stable"
            Save-Config
            Clear-UpdateCache
            Write-Ok "$displayName 安装完成 (共 $($files.Count) 个文件)"
        } else {
            Write-Warn "$displayName 安装不完整，请关闭游戏后重试。"
        }
    }

    Write-Host ""
    Write-Host "  ──────────────────────────────────" -ForegroundColor DarkGray
    Write-Ok "模组安装完成！"

    if (Enable-ModsInSettings) {
        Write-Ok "已自动启用游戏模组开关。"
    }

    Write-Host ""
    Write-Info "提示: 杀戮尖塔2的模组存档和原版存档是分开的。"
    Write-Info "首次使用模组时，模组存档为空（新档）。"
    Write-Host ""

    $steamId = Get-SteamId
    if ($steamId) {
        $hasNormal = $false
        $hasModded = $false
        $normalSummary = @()
        $moddedSummary = @()
        $normalSummaryInfos = @()
        $moddedSummaryInfos = @()
        for ($s = 1; $s -le 3; $s++) {
            $ni = Get-ProfileInfo $steamId "normal" $s
            $mi = Get-ProfileInfo $steamId "modded" $s
            $normalSummaryInfos += $ni
            $moddedSummaryInfos += $mi
            if ($ni.HasData) {
                $hasNormal = $true
                $ts = $ni.LastModified.ToString("MM-dd HH:mm")
                $normalSummary += "槽位${s}:有($ts)"
            } else {
                $normalSummary += "槽位${s}:空"
            }
            if ($mi.HasData) {
                $hasModded = $true
                $ts = $mi.LastModified.ToString("MM-dd HH:mm")
                $moddedSummary += "槽位${s}:有($ts)"
            } else {
                $moddedSummary += "槽位${s}:空"
            }
        }
        Write-Host "  原版存档: $($normalSummary -join '  ')" -ForegroundColor Green
        Write-Host "  模组存档: $($moddedSummary -join '  ')" -ForegroundColor Yellow
        Write-Host ""

        if ($hasNormal) {
            $moddedNewer = $false
            $newestNormal = $null
            $newestModded = $null
            for ($s = 0; $s -lt 3; $s++) {
                if ($normalSummaryInfos[$s].HasData) {
                    if (-not $newestNormal -or $normalSummaryInfos[$s].LastModified -gt $newestNormal) {
                        $newestNormal = $normalSummaryInfos[$s].LastModified
                    }
                }
                if ($moddedSummaryInfos[$s].HasData) {
                    if (-not $newestModded -or $moddedSummaryInfos[$s].LastModified -gt $newestModded) {
                        $newestModded = $moddedSummaryInfos[$s].LastModified
                    }
                }
            }
            if ($newestModded -and $newestNormal -and $newestModded -gt $newestNormal) {
                $moddedNewer = $true
            }

            if ($moddedNewer) {
                Write-Host ""
                Write-Warn "检测到模组存档比原版存档更新！"
                Write-Warn "你可能正在更新模组，复制原版存档会覆盖你现有的模组进度。"
                Write-Info "是否要将原版存档复制到模组存档？（会自动备份，但恢复较麻烦）"
                Write-Host ""
                Write-Host "  复制存档？ [y/N]: " -ForegroundColor Yellow -NoNewline
                [System.Windows.Forms.SendKeys]::SendWait("N")
                $copy = Read-Host
                if ($null -eq $copy) { $copy = "" }
                $copy = $copy.Trim()
                if ($copy -ieq "Y") {
                    Copy-SaveToModded
                } else {
                    Write-Ok "已跳过存档复制。"
                }
            } else {
                Write-Info "是否要将原版存档复制到模组存档？（会自动备份）"
                Write-Host ""
                $copy = Read-Choice "复制存档？ [Y/N]: "
                if ($copy -ieq "Y") {
                    Copy-SaveToModded
                }
            }
        } else {
            Write-Dim "  没有原版存档可复制，跳过。"
        }
    }

    Pause-AndReturn
}

# ============================================================
#  功能: 启用游戏中的模组开关 (修改 settings.save)
# ============================================================
function Enable-ModsInSettings {
    $steamRoot = $script:SAVE_ROOT
    if (-not (Test-Path $steamRoot)) { return $false }

    $changed = $false
    foreach ($idDir in (Get-ChildItem $steamRoot -Directory)) {
        $settingsFile = Join-Path $idDir.FullName "settings.save"
        if (Test-Path $settingsFile) {
            try {
                $json = Get-Content $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($json.mod_settings -and $json.mod_settings.mods_enabled -ne $true) {
                    $json.mod_settings.mods_enabled = $true
                    $json | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
                    $changed = $true
                }
            } catch {
                Write-Warn "修改 settings.save 失败: $_"
            }
        }
    }
    return $changed
}

# ============================================================
#  功能: 卸载后提示存档切换警告
# ============================================================

# ============================================================
#  功能: 卸载后提示存档切换警告
# ============================================================
function Show-ModDisableWarning {
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "  ║            ⚠  重要：存档切换提醒  ⚠               ║" -ForegroundColor Yellow
    Write-Host "  ║                                                      ║" -ForegroundColor Yellow
    Write-Host "  ║  关闭模组后，游戏将切回【原版存档】。               ║" -ForegroundColor Yellow
    Write-Host "  ║  模组存档和原版存档是分开存储、互不影响的。         ║" -ForegroundColor Yellow
    Write-Host "  ║                                                      ║" -ForegroundColor Yellow
    Write-Host "  ║  · 你在模组模式下的进度保存在【模组存档】中        ║" -ForegroundColor Yellow
    Write-Host "  ║  · 关闭模组后看到的是之前的【原版存档】            ║" -ForegroundColor Yellow
    Write-Host "  ║  · 重新开启模组后，模组存档还在，不会丢失          ║" -ForegroundColor Yellow
    Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Yellow
}

# ============================================================
#  功能: 卸载模组（执行删除）
# ============================================================
function Remove-ModFiles($toRemove) {
    $configChanged = $false
    foreach ($mod in $toRemove) {
        Write-Info "正在卸载: $($mod.Name) ..."

        $dirRemoved = $true
        if (-not $mod.IsLoose) {
            try {
                Remove-Item $mod.FullName -Recurse -Force -ErrorAction Stop
            } catch {
                Write-Warn "部分文件可能被锁定，尝试强制删除..."
                try {
                    Get-ChildItem $mod.FullName -File -ErrorAction SilentlyContinue | ForEach-Object {
                        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                    }
                    Remove-Item $mod.FullName -Recurse -Force -ErrorAction SilentlyContinue
                } catch {}
            }
            $dirRemoved = (-not (Test-Path $mod.FullName))
        }

        $looseAction = if ($mod.IsLoose) { "删除根目录 loose 文件" } elseif ($mod.HasLooseDuplicate) { "清理根目录 loose 文件" } else { "" }
        $looseRemoved = Remove-LooseModFiles $mod.ModsDir $mod.Name $looseAction
        $hasLooseRemaining = (@(Get-LooseModFiles $mod.ModsDir $mod.Name).Count -gt 0)

        if ($dirRemoved -and -not $hasLooseRemaining -and $looseRemoved) {
            Set-InstalledChannel -ModName $mod.Name -Channel "stable"
            $configChanged = $true
            Write-Ok "$($mod.Name) 已卸载"
        } else {
            Write-Err "卸载失败，请关闭游戏后重试。"
        }
    }
    if ($configChanged) {
        Save-Config
        Clear-UpdateCache
    }
}

# ============================================================
#  功能: 卸载后检查是否需要关闭模组开关
# ============================================================
function Check-DisableModsAfterUninstall($gameDir, $uninstallAll) {
    $remaining = Get-InstalledMods $gameDir
    $shouldDisable = $uninstallAll -or ($remaining.Count -eq 0)

    if (-not $shouldDisable) { return }

    Write-Host ""
    Write-Host "  ══════════════════════════════════════════════" -ForegroundColor Red
    if ($uninstallAll) {
        Write-Host "  所有模组已卸载。" -ForegroundColor Red
    } else {
        Write-Host "  已无剩余模组。" -ForegroundColor Red
    }
    Write-Host "  ══════════════════════════════════════════════" -ForegroundColor Red

    Show-ModDisableWarning
    Write-Host ""
    Write-Info "如需切回原版存档，请在游戏设置中手动关闭模组开关。"
}

# ============================================================
#  功能: 卸载模组
# ============================================================
function Uninstall-Mod {
    $gameDir = Ensure-GameDir
    if (-not $gameDir) {
        Write-Err "无法确定游戏目录。"
        Pause-AndReturn
        return
    }

    Write-Title "卸载模组"

    $mods = @(Get-InstalledMods $gameDir | Sort-Object Name)
    if ($mods.Count -eq 0) {
        Write-Info "没有已安装的模组。"
        Pause-AndReturn
        return
    }

    Write-Info "已安装模组:"
    Write-Host ""
    $uninstallRows = @()
    for ($i = 0; $i -lt $mods.Count; $i++) {
        $mod = $mods[$i]
        $manifest = $mod.Manifest
        $installName = [string]$mod.Name
        $version = if ($manifest -and $manifest.version) { [string]$manifest.version } else { "" }
        $channel = Get-InstalledChannel $installName
        $stableNotice = if ($mod.IsLoose) { "【可卸载】Loose 布局" } else { "【可卸载】当前已安装" }
        if ($mod.HasLooseDuplicate) {
            $stableNotice += "（根目录另有重复 loose 文件）"
        }
        if ($channel -eq "beta") {
            $betaNotice = "【测试版】卸载后仍保留测试资格"
            if ($mod.IsLoose) { $betaNotice += " / Loose 布局" }
            if ($mod.HasLooseDuplicate) { $betaNotice += " / 根目录另有重复 loose 文件" }
            $uninstallRows += (New-MenuEntry -Name $installName -Version $version -Channel "beta" -InstalledChannel "beta" -InstalledVersion $version -ActionKind "menu_uninstall_beta" -Notice $betaNotice)
        } else {
            $uninstallRows += (New-MenuEntry -Name $installName -Version $version -Channel "stable" -InstalledChannel "stable" -InstalledVersion $version -ActionKind "menu_uninstall" -Notice $stableNotice)
        }
    }

    $widths = Get-UpdateTableWidths -Rows $uninstallRows
    Write-UpdateTableHeader -Widths $widths
    for ($i = 0; $i -lt $uninstallRows.Count; $i++) {
        $row = $uninstallRows[$i]
        Write-UpdateTableRow -Prefix "$($i + 1)." -PrefixColor $(if ($row.ActionKind -eq "menu_uninstall_beta") { "Magenta" } else { "Yellow" }) -Entry $row -IsCurrent $false -Widths $widths
    }
    Write-Host ""
    Write-Host "    A. 卸载全部并关闭模组" -ForegroundColor Red
    Write-Host "    0. 返回主菜单" -ForegroundColor DarkGray
    $choice = Read-Choice "请选择要卸载的模组 [编号/A/0]: "

    if ($choice -eq "0") { return }

    if ($choice -ieq "A") {
        # ── 卸载全部：直接清空整个 mods 文件夹 ──
        Write-Host ""
        Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "  ║         ⚠  即将卸载全部模组并关闭模组开关  ⚠       ║" -ForegroundColor Red
        Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Red
        Show-ModDisableWarning
        Write-Host ""
        $confirm = Read-Choice "确认卸载全部模组？输入 Y 确认: "
        if ($confirm -ine "Y") { Write-Info "已取消。"; Pause-AndReturn; return }

        $modsDir = Join-Path $gameDir "mods"
        Write-Info "正在清空 mods 文件夹..."
        try {
            Get-ChildItem $modsDir -Force | Remove-Item -Recurse -Force
            Write-Ok "mods 文件夹已清空"
        } catch {
            Write-Warn "部分文件可能被锁定，尝试强制删除..."
            Get-ChildItem $modsDir -Force | ForEach-Object {
                Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
            $remaining = Get-ChildItem $modsDir -Force
            if ($remaining.Count -eq 0) {
                Write-Ok "mods 文件夹已清空"
            } else {
                Write-Err "部分文件删除失败，请关闭游戏后重试。"
            }
        }
        Check-DisableModsAfterUninstall $gameDir $true
    } else {
        # ── 卸载单个/多个 ──
        $parts = $choice -replace '，', ',' -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        $toRemove = @()
        $invalid = $false
        foreach ($p in $parts) {
            $idx = 0
            if (-not [int]::TryParse($p, [ref]$idx)) { $invalid = $true; break }
            $idx = $idx - 1
            if ($idx -lt 0 -or $idx -ge $mods.Count) { $invalid = $true; break }
            $toRemove += @($mods[$idx])
        }
        if ($invalid -or $toRemove.Count -eq 0) {
            Write-Err "无效选择。"
            Pause-AndReturn
            return
        }

        $names = ($toRemove | ForEach-Object { $_.Name }) -join ", "
        $confirm = Read-Choice "确认要卸载 $names 吗？输入 Y 确认: "
        if ($confirm -ine "Y") { Write-Info "已取消。"; Pause-AndReturn; return }

        Remove-ModFiles $toRemove
        Check-DisableModsAfterUninstall $gameDir $false
    }

    Pause-AndReturn
}

# ============================================================
#  功能: 查看已安装模组
# ============================================================
function Show-InstalledMods {
    $gameDir = Ensure-GameDir
    if (-not $gameDir) {
        Write-Err "无法确定游戏目录。"
        Pause-AndReturn
        return
    }

    Write-Title "已安装模组"
    Write-Info "游戏目录: $gameDir"
    Write-Info "模组目录: $(Join-Path $gameDir 'mods')"
    Write-Host ""

    $mods = Get-InstalledMods $gameDir
    if ($mods.Count -eq 0) {
        Write-Info "没有已安装的模组。"
    } else {
        $mods = @($mods | Sort-Object Name)
        $installedRows = @()
        foreach ($mod in $mods) {
            $manifest = $mod.Manifest
            $installName = [string]$mod.Name
            $version = if ($manifest -and $manifest.version) { [string]$manifest.version } else { "" }
            $channel = Get-InstalledChannel $installName
            $files = @(Get-InstalledModFiles $mod)
            $fileCount = $files.Count
            $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
            $sizeText = Format-FileSizeText $totalBytes
            $layoutText = if ($mod.IsLoose) { "Loose" } else { "目录" }
            $notice = "【已安装】$layoutText / $fileCount 个文件 / $sizeText"
            if ($mod.HasLooseDuplicate) {
                $notice += " / 检测到同名根目录 loose 文件（当前以目录版为准）"
            }

            if ($channel -eq "beta") {
                $installedRows += (New-MenuEntry -Name $installName -Version $version -Channel "beta" -InstalledChannel "beta" -InstalledVersion $version -ActionKind "menu_installed_beta" -Notice $notice)
            } else {
                $installedRows += (New-MenuEntry -Name $installName -Version $version -Channel "stable" -InstalledChannel "stable" -InstalledVersion $version -ActionKind "menu_installed" -Notice $notice)
            }
        }

        $widths = Get-UpdateTableWidths -Rows $installedRows
        Write-UpdateTableHeader -Widths $widths
        for ($i = 0; $i -lt $installedRows.Count; $i++) {
            $row = $installedRows[$i]
            $prefixColor = if ($row.ActionKind -eq "menu_installed_beta") { "Magenta" } else { "Cyan" }
            Write-UpdateTableRow -Prefix "$($i + 1)." -PrefixColor $prefixColor -Entry $row -IsCurrent $false -Widths $widths
        }

        Write-Host ""
        Write-Dim "共 $($mods.Count) 个模组"
        $choice = Read-Choice "按 D=查看文件详情 / Enter=返回: "
        if ($choice -eq "D" -or $choice -eq "d") {
            Write-Host ""
            foreach ($mod in $mods) {
                $label = Get-InstalledModLabel $mod
                Write-Host "    $label" -ForegroundColor White
                if ($mod.HasLooseDuplicate) {
                    Write-Host "      [!] 检测到 mods 根目录同名 loose 文件：游戏里当前以目录版为准" -ForegroundColor Yellow
                    Write-Host "          如果你继续用模组管理器安装 / 更新 / 卸载这个模组，脚本会自动清理这些根文件" -ForegroundColor DarkYellow
                }
                $files = Get-InstalledModFiles $mod
                foreach ($f in $files) {
                    $size = Format-FileSizeText $f.Length
                    Write-Host "      $($f.Name)  ($size)" -ForegroundColor DarkGray
                }
                Write-Host ""
            }
            Pause-AndReturn
            return
        }
    }

    Pause-AndReturn
}

# ============================================================
#  功能: 存档同步（双向复制）
# ============================================================
function Do-SyncCopy($steamId, $srcType, $srcSlot, $dstType, $dstSlot) {
    if (-not (Assert-SaveOperationSafe "存档同步")) { return }

    $srcLabel = if ($srcType -eq "normal") { "原版A$srcSlot" } else { "模组B$srcSlot" }
    $dstLabel = if ($dstType -eq "normal") { "原版A$dstSlot" } else { "模组B$dstSlot" }

    $srcRoot = Get-ProfileRootPath $steamId $srcType $srcSlot
    $dstInfo = Get-ProfileInfo $steamId $dstType $dstSlot
    $dstRoot = Get-ProfileRootPath $steamId $dstType $dstSlot

    Write-Host ""

    if (-not (Assert-TargetSlotInitialized $dstInfo $dstLabel "存档同步")) { return }

    # Backup if target has data
    if ($dstInfo.HasData) {
        Write-Info "正在备份 $dstLabel..."
        Do-Backup $steamId $dstType "auto_before_sync" $dstSlot
    }

    $result = Copy-ManagedProfileData $srcRoot $dstRoot -IncludeBackups -IncludeReplay
    foreach ($key in $result.SaveKeys) {
        Write-Host "    [√] $([IO.Path]::GetFileName($key))" -ForegroundColor Green
    }
    if ($result.BackupKeys.Count -gt 0) {
        Write-Host "    [√] *.backup ($($result.BackupKeys.Count) 个文件)" -ForegroundColor Green
    }
    if ($result.HistoryCount -gt 0) {
        Write-Host "    [√] history/ ($($result.HistoryCount) 个文件)" -ForegroundColor Green
    }
    if ($result.HasReplay) {
        Write-Host "    [√] replays/latest.mcr" -ForegroundColor Green
    }

    Write-Host ""
    if ($result.Count -gt 0) {
        Write-Ok "同步完成！$srcLabel → $dstLabel（共 $($result.Count) 个文件）"
        # 同步 Steam 云缓存
        $cloudSynced = Sync-SteamCloudCache $steamId $dstType $dstSlot
        if (-not $cloudSynced) {
            Write-Warn "Steam 云缓存校验未通过，请先不要启动游戏。"
        }
    } else {
        Write-Warn "没有文件被复制。"
    }
}

function Sync-SaveCustom($steamId, $nInfos, $mInfos) {
    Write-Host ""
    Write-Info "自定义复制 — 选择来源和目标"
    Write-Host ""

    $availableNormalTargets = Get-InitializedSlotNumbers $nInfos
    $availableModdedTargets = Get-InitializedSlotNumbers $mInfos

    # Show all slots
    Write-Info "可用槽位:"
    for ($i = 0; $i -lt 3; $i++) {
        $s = $i + 1
        $nText = Get-SlotText "A" $s $nInfos[$i]
        $nColor = if ($nInfos[$i].HasData) { "Green" } else { "DarkGray" }
        Write-Host "    $nText" -ForegroundColor $nColor
    }
    for ($i = 0; $i -lt 3; $i++) {
        $s = $i + 1
        $mText = Get-SlotText "B" $s $mInfos[$i]
        $mColor = if ($mInfos[$i].HasData) { "Yellow" } else { "DarkGray" }
        Write-Host "    $mText" -ForegroundColor $mColor
    }

    Write-Host ""
    if ($availableNormalTargets.Count -gt 0) {
        Write-Dim "  可作为原版目标的槽位: A$($availableNormalTargets -join '/A')"
    } else {
        Write-Dim "  原版当前没有已初始化槽位"
    }
    if ($availableModdedTargets.Count -gt 0) {
        Write-Dim "  可作为模组目标的槽位: B$($availableModdedTargets -join '/B')"
    } else {
        Write-Dim "  模组当前没有已初始化槽位"
    }

    Write-Host ""
    $srcInput = (Read-Choice "来源 (如 A1/B2): ").ToUpper()
    if (-not ($srcInput -match '^([AB])([1-3])$')) {
        Write-Err "无效输入，格式: A1/A2/A3/B1/B2/B3"
        Pause-AndReturn
        return
    }
    $srcSide = $Matches[1]
    $srcSlot = [int]$Matches[2]
    $srcType = if ($srcSide -eq "A") { "normal" } else { "modded" }
    $srcInfo = if ($srcSide -eq "A") { $nInfos[$srcSlot-1] } else { $mInfos[$srcSlot-1] }

    if (-not $srcInfo.HasData) {
        Write-Warn "$srcInput 是空的，无法作为来源。"
        Pause-AndReturn
        return
    }

    $dstInput = (Read-Choice "目标 (如 A1/B2): ").ToUpper()
    if (-not ($dstInput -match '^([AB])([1-3])$')) {
        Write-Err "无效输入，格式: A1/A2/A3/B1/B2/B3"
        Pause-AndReturn
        return
    }
    $dstSide = $Matches[1]
    $dstSlot = [int]$Matches[2]
    $dstType = if ($dstSide -eq "A") { "normal" } else { "modded" }
    $dstInfo = if ($dstSide -eq "A") { $nInfos[$dstSlot-1] } else { $mInfos[$dstSlot-1] }

    if ($srcInput -eq $dstInput) {
        Write-Warn "来源和目标不能相同。"
        Pause-AndReturn
        return
    }

    $srcLabel = if ($srcSide -eq "A") { "原版$srcInput" } else { "模组$srcInput" }
    $dstLabel = if ($dstSide -eq "A") { "原版$dstInput" } else { "模组$dstInput" }
    if (-not (Assert-TargetSlotInitialized $dstInfo $dstLabel "存档复制")) {
        Pause-AndReturn
        return
    }

    Write-Host ""

    if ($dstInfo.HasData) {
        Write-Warn "$dstLabel 已有存档，将自动备份后覆盖。"
    }

    $confirm = Read-Choice "确认复制 $srcLabel → $dstLabel？[Y/N]: "
    if ($confirm -ine "Y") { return }

    Do-SyncCopy $steamId $srcType $srcSlot $dstType $dstSlot
    Pause-AndReturn
}

function Sync-Save {
    $steamId = Get-SteamId
    if (-not $steamId) { Pause-AndReturn; return }

    while ($true) {
        Clear-Host
        Write-Title "存档同步"

        # Scan all slots
        $nInfos = @()
        $mInfos = @()
        for ($i = 1; $i -le 3; $i++) {
            $nInfos += Get-ProfileInfo $steamId "normal" $i
            $mInfos += Get-ProfileInfo $steamId "modded" $i
        }

        # Side-by-side display
        $col = 30
        Write-Padded "  原版存档" $col "Green"
        Write-Host "模组存档" -ForegroundColor Yellow
        Write-Padded "  ──────────────────────" $col "DarkGray"
        Write-Host "──────────────────────" -ForegroundColor DarkGray

        for ($i = 0; $i -lt 3; $i++) {
            $nText = Get-SlotText "A" ($i+1) $nInfos[$i]
            $mText = Get-SlotText "B" ($i+1) $mInfos[$i]
            $nColor = if ($nInfos[$i].HasData) { "Green" } else { "DarkGray" }
            $mColor = if ($mInfos[$i].HasData) { "Yellow" } else { "DarkGray" }
            Write-Padded "  $nText" $col $nColor
            Write-Host $mText -ForegroundColor $mColor
        }

        # Quick actions: B→A (most common)
        Write-Host ""
        Write-Host "  模组 → 原版（常用）:" -ForegroundColor Cyan
        for ($i = 0; $i -lt 3; $i++) {
            $s = $i + 1
            $label = "    $s. B$s → A$s"
            if (-not $mInfos[$i].HasData) {
                Write-Host "$label  (来源为空)" -ForegroundColor DarkGray
            } elseif (-not $nInfos[$i].HasData) {
                Write-Host "$label  (目标未初始化)" -ForegroundColor DarkGray
            } else {
                Write-Host $label -ForegroundColor White
            }
        }

        # Quick actions: A→B
        Write-Host ""
        Write-Host "  原版 → 模组:" -ForegroundColor Cyan
        for ($i = 0; $i -lt 3; $i++) {
            $s = $i + 1
            $n = $s + 3
            $label = "    $n. A$s → B$s"
            if (-not $nInfos[$i].HasData) {
                Write-Host "$label  (来源为空)" -ForegroundColor DarkGray
            } elseif (-not $mInfos[$i].HasData) {
                Write-Host "$label  (目标未初始化)" -ForegroundColor DarkGray
            } else {
                Write-Host $label -ForegroundColor White
            }
        }

        Write-Host ""
        Write-Host "    C. 自定义复制（跨槽位）" -ForegroundColor White
        Write-Host "    0. 返回" -ForegroundColor DarkGray

        $choice = Read-Choice "请选择 [1-6/C/0]: "

        if ($choice -eq "0") { return }

        if ($choice -ieq "C") {
            Sync-SaveCustom $steamId $nInfos $mInfos
            continue
        }

        $num = 0
        try { $num = [int]$choice } catch { continue }

        if ($num -ge 1 -and $num -le 3) {
            # B→A (modded to vanilla)
            $slot = $num
            if (-not $mInfos[$slot-1].HasData) {
                Write-Warn "模组槽位 B$slot 是空的，无法复制。"
                Pause-AndReturn
                continue
            }
            if (-not $nInfos[$slot-1].HasData) {
                Write-Warn "原版槽位 A$slot 尚未初始化。请先进游戏创建一次初始存档，再回来复制。"
                Pause-AndReturn
                continue
            }

            Write-Host ""
            if ($nInfos[$slot-1].HasData) {
                Write-Warn "原版槽位 A$slot 已有存档，将自动备份后覆盖。"
            }
            $confirm = Read-Choice "确认复制 模组B$slot → 原版A$slot？[Y/N]: "
            if ($confirm -ine "Y") { continue }

            Do-SyncCopy $steamId "modded" $slot "normal" $slot
            Pause-AndReturn
        }
        elseif ($num -ge 4 -and $num -le 6) {
            # A→B (vanilla to modded)
            $slot = $num - 3
            if (-not $nInfos[$slot-1].HasData) {
                Write-Warn "原版槽位 A$slot 是空的，无法复制。"
                Pause-AndReturn
                continue
            }
            if (-not $mInfos[$slot-1].HasData) {
                Write-Warn "模组槽位 B$slot 尚未初始化。请先进游戏创建一次初始存档，再回来复制。"
                Pause-AndReturn
                continue
            }

            Write-Host ""
            if ($mInfos[$slot-1].HasData) {
                Write-Warn "模组槽位 B$slot 已有存档，将自动备份后覆盖。"
            }
            $confirm = Read-Choice "确认复制 原版A$slot → 模组B$slot？[Y/N]: "
            if ($confirm -ine "Y") { continue }

            Do-SyncCopy $steamId "normal" $slot "modded" $slot
            Pause-AndReturn
        }
    }
}

# ============================================================
#  功能: 存档管理
# ============================================================
function Show-SaveMenu {
    while ($true) {
        Clear-Host
        Write-Title "存档管理"
        Write-Info "杀戮尖塔2 存档说明:"
        Write-Info "  · 原版存档与模组存档是完全分开的"
        Write-Info "  · 启用模组后，游戏会使用单独的模组存档"
        Write-Info "  · 首次使用模组时，模组存档为空（相当于新号）"
        Write-Info "  · 可以在原版存档与模组存档之间双向同步"
        Write-Info "  · 进行复制/恢复前，请先完全退出游戏和 Steam"
        Write-Info "  · 目标槽位必须先在游戏里初始化，不能直接写入空槽位"
        Write-Host ""
        Write-Dim "存档目录: $($script:SAVE_ROOT)"
        Write-Host ""
        Write-Host "    1. 复制原版存档到模组存档" -ForegroundColor Cyan
        Write-Host "       (推荐第一次安装使用)" -ForegroundColor DarkGray
        Write-Host "    2. 复制模组存档回原版存档" -ForegroundColor Cyan
        Write-Host "       (推荐关闭模组时使用，同步进度回去)" -ForegroundColor DarkGray
        Write-Host "    3. 存档同步 (高级)" -ForegroundColor White
        Write-Host "       (原版↔模组 双向对比，快捷键操作)" -ForegroundColor DarkGray
        Write-Host "    4. 备份原版存档"
        Write-Host "    5. 备份模组存档"
        Write-Host "    6. 查看存档状态"
        Write-Host "    7. 恢复备份"
        Write-Host "    0. 返回主菜单" -ForegroundColor DarkGray

        $choice = Read-Choice "请选择 [0-7]: "
        switch ($choice) {
            "1" { Copy-SaveToModded; Pause-AndReturn }
            "2" { Copy-SaveToNormal; Pause-AndReturn }
            "3" { Sync-Save }
            "4" { Backup-Save "normal"; Pause-AndReturn }
            "5" { Backup-Save "modded"; Pause-AndReturn }
            "6" { Show-SaveStatus; Pause-AndReturn }
            "7" { Restore-Backup; Pause-AndReturn }
            "0" { return }
        }
    }
}

function Show-SaveStatus {
    Write-Host ""
    $steamId = Get-SteamId
    if (-not $steamId) { return }

    Write-Host ""
    Write-Host "  Steam ID: $steamId" -ForegroundColor Cyan

    foreach ($type in @("normal", "modded")) {
        $label = if ($type -eq "normal") { "原版存档" } else { "模组存档" }
        $color = if ($type -eq "normal") { "Green" } else { "Yellow" }
        Write-Host ""
        Write-Host "  [$label]" -ForegroundColor $color
        for ($i = 1; $i -le 3; $i++) {
            $info = Get-ProfileInfo $steamId $type $i
            if ($info.HasData) {
                $ts = $info.LastModified.ToString("yyyy-MM-dd HH:mm")
                $hasRun = Test-Path (Join-Path $info.Path "current_run.save")
                $detail = "上次修改: $ts"
                if ($hasRun) { $detail += " | 有进行中的一局" }
                Write-Host "    槽位${i}: $detail" -ForegroundColor $color
            } else {
                Write-Host "    槽位${i}: (空)" -ForegroundColor DarkGray
            }
        }
    }

    Write-Host ""

    # 备份
    $backupDir = Join-Path $script:SAVE_ROOT "$steamId\backups"
    Write-Host "  [备份]" -ForegroundColor Magenta
    if (Test-Path $backupDir) {
        $backups = Get-ChildItem $backupDir -Directory | Sort-Object Name -Descending
        if ($backups.Count -eq 0) {
            Write-Dim "    (无备份)"
        } else {
            foreach ($bk in $backups) {
                $fileCount = (Get-ChildItem $bk.FullName -File -Recurse -ErrorAction SilentlyContinue).Count
                $profileLabel = ""
                if ($bk.Name -match '_p(\d)_') { $profileLabel = "槽位$($Matches[1]), " }
                Write-Host "    $($bk.Name)  ($profileLabel$fileCount 个文件)" -ForegroundColor DarkGray
            }
        }
    } else {
        Write-Dim "    (无备份)"
    }
}

function Copy-SaveDirection($srcType, $dstType) {
    $srcLabel = if ($srcType -eq "normal") { "原版" } else { "模组" }
    $dstLabel = if ($dstType -eq "normal") { "原版" } else { "模组" }
    $srcColor = if ($srcType -eq "normal") { "Green" } else { "Yellow" }
    $dstColor = if ($dstType -eq "normal") { "Green" } else { "Yellow" }

    Write-Host ""
    Write-Info "── 复制${srcLabel}存档到${dstLabel}存档 ──"
    Write-Host ""

    $steamId = Get-SteamId
    if (-not $steamId) { return }

    Write-Host "  Steam ID: $steamId" -ForegroundColor Cyan
    Write-Host ""

    # Scan all 3 profiles
    $srcInfos = @()
    $dstInfos = @()
    for ($i = 1; $i -le 3; $i++) {
        $srcInfos += Get-ProfileInfo $steamId $srcType $i
        $dstInfos += Get-ProfileInfo $steamId $dstType $i
    }

    # Check if any source profile has data
    $hasAnySrc = $false
    for ($i = 0; $i -lt 3; $i++) {
        if ($srcInfos[$i].HasData) { $hasAnySrc = $true; break }
    }
    if (-not $hasAnySrc) {
        Write-Err "没有可复制的${srcLabel}存档。"
        return
    }

    # Auto-select: source = first non-empty src, dest = same-slot initialized target or first initialized target.
    $srcSlot = 0
    for ($i = 0; $i -lt 3; $i++) {
        if ($srcInfos[$i].HasData) { $srcSlot = $i + 1; break }
    }
    $dstSlot = Get-PreferredTargetSlot $srcSlot $dstInfos
    if ($dstSlot -eq 0) {
        Write-Err "没有可用的${dstLabel}目标槽位。"
        Write-Warn "请先进入游戏，在任意${dstLabel}槽位创建一次初始存档，再回来复制。"
        return
    }

    # Interactive loop with arrow indicators
    while ($true) {
        Write-Host "  [${srcLabel}存档 — 来源]" -ForegroundColor $srcColor
        for ($i = 0; $i -lt 3; $i++) {
            $p = $srcInfos[$i]
            $arrow = if ($i + 1 -eq $srcSlot) { " ◄ 来源" } else { "" }
            if ($p.HasData) {
                $ts = $p.LastModified.ToString("yyyy-MM-dd HH:mm")
                Write-Host "    槽位$($i+1): 有存档  $ts" -ForegroundColor $srcColor -NoNewline
                if ($arrow) { Write-Host $arrow -ForegroundColor Cyan } else { Write-Host "" }
            } else {
                Write-Host "    槽位$($i+1): (空)" -ForegroundColor DarkGray
            }
        }

        Write-Host ""

        Write-Host "  [${dstLabel}存档 — 目标]" -ForegroundColor $dstColor
        for ($i = 0; $i -lt 3; $i++) {
            $p = $dstInfos[$i]
            $arrow = if ($i + 1 -eq $dstSlot) { " ◄ 目标" } else { "" }
            if ($p.HasData) {
                $ts = $p.LastModified.ToString("yyyy-MM-dd HH:mm")
                Write-Host "    槽位$($i+1): 有存档  $ts" -ForegroundColor $dstColor -NoNewline
                if ($arrow) { Write-Host $arrow -ForegroundColor Cyan } else { Write-Host "" }
            } else {
                Write-Host "    槽位$($i+1): (空，不可选)" -ForegroundColor DarkGray -NoNewline
                if ($arrow) { Write-Host $arrow -ForegroundColor Cyan } else { Write-Host "" }
            }
        }

        Write-Host ""
        Write-Host "  ─────────────────────────────────" -ForegroundColor DarkGray
        $dstNote = " (将覆盖，自动备份)"
        Write-Host "  计划: ${srcLabel}槽位$srcSlot → ${dstLabel}槽位$dstSlot$dstNote" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "    S. 更改来源槽位 (当前: $srcSlot)"
        Write-Host "    D. 更改目标槽位 (当前: $dstSlot)"
        Write-Host "    Y. 确认执行" -ForegroundColor Cyan
        Write-Host "    0. 取消" -ForegroundColor DarkGray

        $choice = Read-Choice "请选择 [S/D/Y/0]: "

        if ($choice -eq "0") { Write-Info "已取消。"; return }
        if ($choice -ieq "Y") {
            if (-not (Assert-TargetSlotInitialized $dstInfos[$dstSlot-1] "${dstLabel}槽位$dstSlot" "存档复制")) {
                continue
            }
            break
        }

        if ($choice -ieq "S") {
            $pick = Read-Choice "选择来源槽位 [1-3]: "
            $idx = [int]$pick
            if ($idx -ge 1 -and $idx -le 3) {
                if ($srcInfos[$idx-1].HasData) {
                    $srcSlot = $idx
                    Write-Ok "来源已更改为: ${srcLabel}槽位$srcSlot"
                } else {
                    Write-Warn "${srcLabel}槽位$idx 是空的，无法作为来源。"
                }
            } else {
                Write-Warn "请输入 1-3。"
            }
            continue
        }

        if ($choice -ieq "D") {
            $pick = Read-Choice "选择目标槽位 [1-3]: "
            $idx = [int]$pick
            if ($idx -ge 1 -and $idx -le 3) {
                if ($dstInfos[$idx-1].HasData) {
                    $dstSlot = $idx
                    Write-Warn "${dstLabel}槽位$idx 已有存档，执行时将自动备份后覆盖。"
                    Write-Ok "目标已更改为: ${dstLabel}槽位$dstSlot"
                } else {
                    Write-Warn "${dstLabel}槽位$idx 当前为空。请先在游戏里初始化一次，再回来覆盖。"
                }
            } else {
                Write-Warn "请输入 1-3。"
            }
            continue
        }
    }

    if (-not (Assert-SaveOperationSafe "存档复制")) { return }

    # Execute copy
    $srcRoot = Get-ProfileRootPath $steamId $srcType $srcSlot
    $dstRoot = Get-ProfileRootPath $steamId $dstType $dstSlot

    Write-Host ""

    if (-not (Assert-TargetSlotInitialized $dstInfos[$dstSlot-1] "${dstLabel}槽位$dstSlot" "存档复制")) { return }

    # Backup if target has data
    if ($dstInfos[$dstSlot-1].HasData) {
        Write-Info "正在备份${dstLabel}槽位$dstSlot 的现有存档..."
        Do-Backup $steamId $dstType "auto_before_copy" $dstSlot
        Write-Host ""
    }

    $result = Copy-ManagedProfileData $srcRoot $dstRoot -IncludeBackups -IncludeReplay
    foreach ($key in $result.SaveKeys) {
        Write-Host "    [√] $([IO.Path]::GetFileName($key))" -ForegroundColor Green
    }
    if ($result.BackupKeys.Count -gt 0) {
        Write-Host "    [√] *.backup ($($result.BackupKeys.Count) 个文件)" -ForegroundColor Green
    }
    if ($result.HistoryCount -gt 0) {
        Write-Host "    [√] history/ ($($result.HistoryCount) 个文件)" -ForegroundColor Green
    }
    if ($result.HasReplay) {
        Write-Host "    [√] replays/latest.mcr" -ForegroundColor Green
    }

    Write-Host ""
    if ($result.Count -gt 0) {
        Write-Ok "存档复制完成！${srcLabel}槽位$srcSlot → ${dstLabel}槽位$dstSlot（共 $($result.Count) 个文件）"

        # 同步 Steam 云缓存，防止云同步覆盖刚复制的文件
        Write-Host ""
        Write-Info "正在同步 Steam 云存档缓存..."
        $cloudSynced = Sync-SteamCloudCache $steamId $dstType $dstSlot
        Write-Host ""
        if (-not $cloudSynced) {
            Write-Warn "Steam 云缓存校验未通过，请先不要启动游戏。"
            return
        }

        if ($dstType -eq "modded") {
            Write-Info "下次启用模组进入游戏时，请选择对应槽位使用复制的进度。"
        } else {
            Write-Info "下次关闭模组进入游戏时，对应槽位已包含最新模组进度。"
        }
    } else {
        Write-Warn "没有文件被复制。"
    }
}

function Copy-SaveToModded {
    Copy-SaveDirection "normal" "modded"
}

function Copy-SaveToNormal {
    Copy-SaveDirection "modded" "normal"
}

function Backup-Save($type) {
    Write-Host ""
    $label = if ($type -eq "normal") { "原版" } else { "模组" }
    Write-Info "── 备份${label}存档 ──"
    Write-Host ""

    $steamId = Get-SteamId
    if (-not $steamId) { return }

    # Show profiles
    $profiles = @()
    $hasAny = $false
    for ($i = 1; $i -le 3; $i++) {
        $info = Get-ProfileInfo $steamId $type $i
        $profiles += $info
        if ($info.HasData) { $hasAny = $true }
    }

    if (-not $hasAny) {
        Write-Info "没有${label}存档可备份。"
        return
    }

    Write-Info "${label}存档槽位:"
    Write-Host ""
    for ($i = 0; $i -lt 3; $i++) {
        $p = $profiles[$i]
        if ($p.HasData) {
            $ts = $p.LastModified.ToString("yyyy-MM-dd HH:mm")
            Write-Host "    $($i+1). 槽位$($i+1): 有存档  $ts" -ForegroundColor White
        } else {
            Write-Host "    $($i+1). 槽位$($i+1): (空)" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    Write-Host "    A. 备份全部非空槽位" -ForegroundColor Cyan
    Write-Host "    0. 返回" -ForegroundColor DarkGray

    $choice = Read-Choice "请选择 [1-3/A/0]: "
    if ($choice -eq "0") { return }

    if ($choice -ieq "A") {
        for ($i = 0; $i -lt 3; $i++) {
            if ($profiles[$i].HasData) {
                Do-Backup $steamId $type "manual" ($i + 1)
            }
        }
    } else {
        $idx = [int]$choice
        if ($idx -ge 1 -and $idx -le 3) {
            if ($profiles[$idx-1].HasData) {
                Do-Backup $steamId $type "manual" $idx
            } else {
                Write-Warn "槽位$idx 是空的，无需备份。"
            }
        } else {
            Write-Err "无效选择。"
        }
    }
}

function Do-Backup($steamId, $type, $tag, $profileId) {
    if (-not $profileId) { $profileId = 1 }
    $label = if ($type -eq "normal") { "原版" } else { "模组" }
    $srcRoot = Get-ProfileRootPath $steamId $type $profileId

    if (-not (Test-Path $srcRoot)) {
        Write-Err "存档目录不存在: $srcRoot"
        return
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDir = Join-Path $script:SAVE_ROOT "$steamId\backups\${type}_p${profileId}_${tag}_$timestamp"
    New-Item $backupDir -ItemType Directory -Force | Out-Null

    $result = Copy-ManagedProfileData $srcRoot $backupDir -IncludeBackups -IncludeReplay

    if ($result.Count -gt 0) {
        Write-Ok "${label}槽位$profileId 备份完成 ($($result.Count) 个文件)"
        Write-Dim "  $backupDir"
    } else {
        Write-Warn "没有存档文件可备份。"
        Remove-Item $backupDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 清理旧备份：每种类型最多保留 20 份
    $backupRoot = Join-Path $script:SAVE_ROOT "$steamId\backups"
    if (Test-Path $backupRoot) {
        $typeBackups = Get-ChildItem $backupRoot -Directory | Where-Object { $_.Name -like "${type}_*" } | Sort-Object Name -Descending
        if ($typeBackups.Count -gt 20) {
            $toRemove = $typeBackups | Select-Object -Skip 20
            foreach ($old in $toRemove) {
                Remove-Item $old.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
            Write-Dim "  已清理 $($toRemove.Count) 份旧的${label}备份（保留最近 20 份）"
        }
    }
}

function Restore-Backup {
    Write-Host ""
    Write-Info "── 恢复备份 ──"
    Write-Host ""

    $steamId = Get-SteamId
    if (-not $steamId) { return }

    $backupRoot = Join-Path $script:SAVE_ROOT "$steamId\backups"
    if (-not (Test-Path $backupRoot)) {
        Write-Info "没有可用的备份。"
        return
    }

    $backups = Get-ChildItem $backupRoot -Directory | Sort-Object Name -Descending
    if ($backups.Count -eq 0) {
        Write-Info "没有可用的备份。"
        return
    }

    Write-Info "可用备份:"
    Write-Host ""
    for ($i = 0; $i -lt $backups.Count; $i++) {
        $bk = $backups[$i]
        $fileCount = (Get-ChildItem $bk.FullName -File -Recurse -ErrorAction SilentlyContinue).Count
        $isNormal = $bk.Name -like "normal_*"
        $typeLabel = if ($isNormal) { "原版" } else { "模组" }
        $color = if ($isNormal) { "Green" } else { "Yellow" }
        # Parse profile ID from backup name (format: type_pN_tag_timestamp)
        $profileId = 1
        if ($bk.Name -match '_p(\d)_') { $profileId = [int]$Matches[1] }
        Write-Host "    $($i+1). [$typeLabel 槽位$profileId] $($bk.Name)  ($fileCount 个文件)" -ForegroundColor $color
    }
    Write-Host ""
    Write-Host "    0. 返回" -ForegroundColor DarkGray
    $choice = Read-Choice "请选择要恢复的备份 [编号/0]: "

    if ($choice -eq "0") { return }
    $idx = [int]$choice - 1
    if ($idx -lt 0 -or $idx -ge $backups.Count) {
        Write-Err "无效选择。"
        return
    }

    $selected = $backups[$idx]
    $isNormal = $selected.Name -like "normal_*"
    # Parse profile ID
    $profileId = 1
    if ($selected.Name -match '_p(\d)_') { $profileId = [int]$Matches[1] }

    # Determine restore target
    $typeLabel = if ($isNormal) { "原版" } else { "模组" }
    $restoreType = if ($isNormal) { "normal" } else { "modded" }
    if ($isNormal) {
        $restoreRoot = Join-Path $script:SAVE_ROOT "$steamId\profile$profileId"
    } else {
        $restoreRoot = Join-Path $script:SAVE_ROOT "$steamId\modded\profile$profileId"
    }

    Write-Host ""
    Write-Info "将恢复到: ${typeLabel}槽位$profileId"
    Write-Dim "  $restoreRoot"
    Write-Host ""

    # Allow changing target profile
    $changeTarget = Read-Choice "恢复到其他槽位？输入槽位号 [1-3] 或直接回车使用槽位${profileId}: "
    if ($changeTarget -match '^[1-3]$') {
        $profileId = [int]$changeTarget
        if ($isNormal) {
            $restoreRoot = Join-Path $script:SAVE_ROOT "$steamId\profile$profileId"
        } else {
            $restoreRoot = Join-Path $script:SAVE_ROOT "$steamId\modded\profile$profileId"
        }
        Write-Ok "已更改为: ${typeLabel}槽位$profileId"
    }

    $restoreInfo = Get-ProfileInfo $steamId $restoreType $profileId
    if (-not (Assert-TargetSlotInitialized $restoreInfo "${typeLabel}槽位$profileId" "备份恢复")) { return }

    $confirm = Read-Choice "确认恢复？输入 Y 确认: "
    if ($confirm -ine "Y") { Write-Info "已取消。"; return }

    if (-not (Assert-SaveOperationSafe "备份恢复")) { return }

    # Backup current save before restoring
    if (Test-Path (Join-Path (Join-Path $restoreRoot "saves") "progress.save")) {
        Write-Info "正在备份当前${typeLabel}槽位$profileId..."
        Do-Backup $steamId $restoreType "auto_before_restore" $profileId
    }

    # Execute restore
    $structuredBackup = (Test-Path (Join-Path $selected.FullName "saves")) -or (Test-Path (Join-Path $selected.FullName "replays"))
    if ($structuredBackup) {
        $fileMap = Get-ManagedProfileFileMap $selected.FullName -IncludeBackups -IncludeReplay
        Reset-ManagedProfileTarget $restoreRoot -IncludeReplay
    } else {
        $fileMap = Get-LegacyBackupFileMap $selected.FullName
        Reset-ManagedProfileTarget $restoreRoot
    }
    $restoredCount = Write-ManagedProfileFileMap $fileMap $restoreRoot

    Write-Host ""
    Write-Ok "恢复完成！共恢复 $restoredCount 个文件到${typeLabel}槽位$profileId。"
    # 同步 Steam 云缓存
    $cloudSynced = Sync-SteamCloudCache $steamId $restoreType $profileId
    if (-not $cloudSynced) {
        Write-Warn "Steam 云缓存校验未通过，请先不要启动游戏。"
    }
}

# ============================================================
#  功能: 设置
# ============================================================
function Show-Settings {
    while ($true) {
        Clear-Host
        Write-Title "设置"

        $dir = Get-GameDir
        Write-Info "当前游戏目录:"
        if ($dir) {
            Write-Host "    $dir" -ForegroundColor Green
        } else {
            Write-Dim "    (未设置)"
        }
        Write-Host ""
        Write-Host "    1. 自动检测游戏目录"
        Write-Host "    2. 手动设置游戏目录"
        Write-Host "    3. 清除配置文件"
        Write-Host "    4. 清理模组备份文件 (.bak)"
        Write-Host "    0. 返回主菜单" -ForegroundColor DarkGray

        $choice = Read-Choice "请选择 [0-4]: "
        switch ($choice) {
            "1" {
                Write-Host ""
                Write-Info "正在自动检测..."
                $found = Find-GameDir
                if ($found) {
                    Write-Ok "检测成功: $found"
                    $script:Config.GameDir = $found
                    Save-Config
                } else {
                    Write-Err "自动检测失败。请尝试手动设置。"
                }
                Pause-AndReturn
            }
            "2" {
                Set-GameDirManual | Out-Null
                Pause-AndReturn
            }
            "3" {
                if (Test-Path $script:CONFIG_FILE) {
                    Remove-Item $script:CONFIG_FILE -Force
                    $script:Config = Get-DefaultConfig
                    Clear-UpdateCache
                    Write-Ok "配置已清除。"
                } else {
                    Write-Info "没有配置文件需要清除。"
                }
                Pause-AndReturn
            }
            "4" {
                $dir = Get-GameDir
                if (-not $dir) { Write-Err "请先设置游戏目录。"; Pause-AndReturn; continue }
                $modsDir = Join-Path $dir "mods"
                $bakFiles = Get-ChildItem $modsDir -Recurse -File -Filter "*.bak*" -ErrorAction SilentlyContinue
                if ($bakFiles.Count -gt 0) {
                    Write-Info "找到 $($bakFiles.Count) 个备份文件:"
                    foreach ($f in $bakFiles) { Write-Dim "  $($f.FullName)" }
                    $confirm = Read-Choice "删除全部？输入 Y 确认: "
                    if ($confirm -ieq "Y") {
                        $bakFiles | Remove-Item -Force
                        Write-Ok "已清理 $($bakFiles.Count) 个备份文件。"
                    }
                } else {
                    Write-Info "没有备份文件需要清理。"
                }
                Pause-AndReturn
            }
            "0" { return }
        }
    }
}

# ============================================================
#  在线更新
# ============================================================

function Get-WebStatusCode {
    param($ErrorRecord)

    $ex = if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) {
        $ErrorRecord.Exception
    } else {
        $ErrorRecord
    }
    if (-not $ex) { return 0 }
    if ($ex.Response -and ($ex.Response -is [System.Net.HttpWebResponse])) {
        try { return [int]$ex.Response.StatusCode } catch {}
    }
    return 0
}

function Should-RetryHttpStatus {
    param([int]$StatusCode)
    if ($StatusCode -eq 0) { return $true }
    return ($StatusCode -ne 400 -and $StatusCode -ne 401 -and $StatusCode -ne 403 -and $StatusCode -ne 404)
}

function Invoke-WithRetry {
    param([string]$Uri, [int]$TimeoutSec = 8, [int]$MaxRetries = 2)
    $attempt = 0
    while ($true) {
        $httpResp = $null
        $json = $null
        try {
            $req = New-HttpRequest -Uri $Uri -Method "GET" -TimeoutSec $TimeoutSec
            $httpResp = $req.GetResponse()
            $stream = $httpResp.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
            $json = $reader.ReadToEnd()
            $reader.Close()
        } catch {
            $attempt++
            $statusCode = Get-WebStatusCode $_
            if ($attempt -gt $MaxRetries -or -not (Should-RetryHttpStatus $statusCode)) { throw $_ }
            Write-Dim "    请求失败，重试中 ($attempt/$MaxRetries): $(Get-WebErrorMessage $_)"
            Start-Sleep -Milliseconds 800
        } finally {
            if ($httpResp) { try { $httpResp.Close() } catch {} }
        }

        if ($null -ne $json) {
            try {
                return $json | ConvertFrom-Json
            } catch {
                throw "服务器返回非法 JSON（catalog / script response）: $($_.Exception.Message)"
            }
        }
    }
}

function Initialize-NetworkStack {
    if ($script:NETWORK_READY) { return }

    try {
        $protocols = [System.Net.SecurityProtocolType]::Tls12
        try { $protocols = $protocols -bor [System.Net.SecurityProtocolType]::Tls13 } catch {}
        [System.Net.ServicePointManager]::SecurityProtocol = $protocols
    } catch {}

    try { [System.Net.ServicePointManager]::Expect100Continue = $false } catch {}
    try { [System.Net.ServicePointManager]::DefaultConnectionLimit = 8 } catch {}
    $script:NETWORK_READY = $true
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
    $req.UserAgent = "STS2ModManager/$($script:VERSION)"
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

function Download-FileWithRetry {
    param(
        [string]$Uri,
        [string]$OutFile,
        [int]$TimeoutSec = 120,
        [int]$MaxRetries = 1
    )

    $attempt = 0
    $tempFile = "$OutFile.download"

    while ($true) {
        $httpResp = $null
        $inputStream = $null
        $outputStream = $null
        try {
            $parent = Split-Path $OutFile -Parent
            if ($parent -and -not (Test-Path $parent)) {
                New-Item -Path $parent -ItemType Directory -Force | Out-Null
            }

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
            return
        } catch {
            $attempt++
            $statusCode = Get-WebStatusCode $_
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            if ($attempt -gt $MaxRetries -or -not (Should-RetryHttpStatus $statusCode)) { throw $_ }
            Write-Dim "    下载失败，重试中 ($attempt/$MaxRetries): $(Get-WebErrorMessage $_)"
            Start-Sleep -Milliseconds 1000
        } finally {
            if ($outputStream) { try { $outputStream.Close() } catch {} }
            if ($inputStream) { try { $inputStream.Close() } catch {} }
            if ($httpResp) { try { $httpResp.Close() } catch {} }
        }
    }
}

function Invoke-JsonPost {
    param(
        [string]$Uri,
        [string]$Body,
        [int]$TimeoutSec = 8,
        [int]$MaxRetries = 1
    )

    $attempt = 0
    while ($true) {
        $httpResp = $null
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
            $req = New-HttpRequest -Uri $Uri -Method "POST" -TimeoutSec $TimeoutSec
            $req.ContentType = "application/json"
            $req.ContentLength = $bytes.Length

            $stream = $req.GetRequestStream()
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Close()

            $httpResp = $req.GetResponse()
            $respStream = $httpResp.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($respStream, [System.Text.Encoding]::UTF8)
            $json = $reader.ReadToEnd()
            $reader.Close()
            if (-not $json) { return $null }
            return $json | ConvertFrom-Json
        } catch {
            $attempt++
            $statusCode = Get-WebStatusCode $_
            if ($attempt -gt $MaxRetries -or -not (Should-RetryHttpStatus $statusCode)) { throw $_ }
            Write-Dim "    请求失败，重试中 ($attempt/$MaxRetries): $(Get-WebErrorMessage $_)"
            Start-Sleep -Milliseconds 800
        } finally {
            if ($httpResp) { try { $httpResp.Close() } catch {} }
        }
    }
}

function Get-HashHex($text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$text)
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash)).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Test-FileSha256 {
    param([string]$FilePath, [string]$ExpectedHash)
    if (-not $ExpectedHash) { return $true }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($FilePath)
        try {
            $hashBytes = $sha.ComputeHash($stream)
            $actual = ([BitConverter]::ToString($hashBytes)).Replace("-", "").ToLowerInvariant()
            return $actual -eq $ExpectedHash.ToLowerInvariant()
        } finally { $stream.Close() }
    } finally { $sha.Dispose() }
}

function Get-OrCreateTelemetryId {
    if ($script:Config.TelemetryId) { return [string]$script:Config.TelemetryId }
    $script:Config.TelemetryId = ([guid]::NewGuid().ToString("N"))
    Save-Config
    return [string]$script:Config.TelemetryId
}

function Get-TelemetryCache {
    if (-not (Test-Path $script:REPORT_CACHE_FILE)) { return $null }
    try {
        $raw = Get-Content $script:REPORT_CACHE_FILE -Raw -Encoding UTF8
        $cache = $raw | ConvertFrom-Json
        if (-not $cache.cache_version -or $cache.cache_version -ne 1) { return $null }
        return $cache
    } catch {
        Remove-Item $script:REPORT_CACHE_FILE -Force -ErrorAction SilentlyContinue
        return $null
    }
}

function Save-TelemetryCache($signature) {
    try {
        @{
            cache_version = 1
            last_report_at = (Get-Date).ToString("o")
            signature = $signature
        } | ConvertTo-Json -Depth 4 | Set-Content $script:REPORT_CACHE_FILE -Encoding UTF8
    } catch {}
}

function Get-TelemetrySignature($mods) {
    $parts = @()
    foreach ($m in ($mods | Sort-Object Id, Version)) {
        $parts += "$($m.Id)@$($m.Version)"
    }
    $raw = "$($script:REPORT_SCHEMA_VERSION)|$($script:VERSION)|" + ($parts -join ";")
    return Get-HashHex $raw
}

function Should-SendTelemetry($signature) {
    $cache = Get-TelemetryCache
    if (-not $cache) { return $true }
    if (-not $cache.signature -or $cache.signature -ne $signature) { return $true }
    try {
        $lastReport = [datetime]::Parse($cache.last_report_at)
        if (((Get-Date) - $lastReport).TotalHours -ge $script:REPORT_TTL_HOURS) { return $true }
    } catch {
        return $true
    }
    return $false
}

function Send-TelemetryReport {
    param([string]$gameDir)

    $mods = @(Get-InstalledModTelemetry $gameDir)
    if ($mods.Count -eq 0) { return $false }

    $clientId = Get-OrCreateTelemetryId
    $signature = Get-TelemetrySignature $mods
    if (-not (Should-SendTelemetry $signature)) { return $false }

    $payload = @{
        schema_version = $script:REPORT_SCHEMA_VERSION
        client_id = $clientId
        mods = @(
            $mods | ForEach-Object {
                @{
                    id = $_.Id
                    version = if ($_.Version) { $_.Version } else { "unknown" }
                }
            }
        )
    } | ConvertTo-Json -Depth 5 -Compress

    try {
        $null = Invoke-JsonPost -Uri "$($script:UPDATE_API)/report" -Body $payload -TimeoutSec 4
        Save-TelemetryCache $signature
        return $true
    } catch {
        return $false
    }
}

# CJK 感知截断（按显示宽度截断，不会越界）
function Truncate-ToWidth($text, $maxWidth) {
    $w = 0
    for ($i = 0; $i -lt $text.Length; $i++) {
        $cw = if ([int]$text[$i] -gt 0x7F) { 2 } else { 1 }
        if ($w + $cw -gt $maxWidth) {
            return $text.Substring(0, $i)
        }
        $w += $cw
    }
    return $text
}

function Clear-UpdateCache {
    Remove-Item $script:CACHE_FILE -Force -ErrorAction SilentlyContinue
}

function Get-BetaEntitlementsMap {
    $script:Config = Ensure-ConfigDefaults $script:Config
    if (-not ($script:Config.BetaEntitlements -is [System.Collections.IDictionary])) {
        $script:Config.BetaEntitlements = @{}
    }
    return $script:Config.BetaEntitlements
}

function Get-InstalledChannelsMap {
    $script:Config = Ensure-ConfigDefaults $script:Config
    if (-not ($script:Config.InstalledChannels -is [System.Collections.IDictionary])) {
        $script:Config.InstalledChannels = @{}
    }
    return $script:Config.InstalledChannels
}

function Get-BetaEntitlement {
    param([string]$ModName)
    $map = Get-BetaEntitlementsMap
    if (-not $map.ContainsKey($ModName)) { return $null }
    $record = ConvertTo-HashtableDeep $map[$ModName]
    if (-not ($record -is [System.Collections.IDictionary])) { return $null }
    return $record
}

function Set-BetaEntitlement {
    param([string]$ModName, [hashtable]$Record)
    $map = Get-BetaEntitlementsMap
    $map[$ModName] = @{
        token = if ($Record.token) { [string]$Record.token } else { "" }
        granted_at = if ($Record.granted_at) { [string]$Record.granted_at } else { "" }
        expires_at = if ($Record.expires_at) { [string]$Record.expires_at } else { "" }
    }
}

function Remove-BetaEntitlement {
    param([string]$ModName)
    $map = Get-BetaEntitlementsMap
    if ($map.ContainsKey($ModName)) {
        $map.Remove($ModName)
        return $true
    }
    return $false
}

function Clear-AllBetaEntitlements {
    $script:Config.BetaEntitlements = @{}
}

function Get-InstalledChannel {
    param([string]$ModName)
    $map = Get-InstalledChannelsMap
    if ($map.ContainsKey($ModName) -and [string]$map[$ModName] -eq "beta") {
        return "beta"
    }
    return "stable"
}

function Set-InstalledChannel {
    param([string]$ModName, [string]$Channel)
    $map = Get-InstalledChannelsMap
    if ($Channel -eq "beta") {
        $map[$ModName] = "beta"
    } elseif ($map.ContainsKey($ModName)) {
        $map.Remove($ModName)
    }
}

function Test-EntitlementExpired {
    param($Record)
    if (-not $Record -or -not $Record.expires_at) { return $false }
    try {
        return ([datetime]::Parse([string]$Record.expires_at) -le (Get-Date).ToUniversalTime())
    } catch {
        return $false
    }
}

function Get-EntitlementsPayload {
    $payload = @{}
    foreach ($modName in (Get-BetaEntitlementsMap).Keys | Sort-Object) {
        $record = Get-BetaEntitlement $modName
        if ($record -and $record.token) {
            $payload[$modName] = [string]$record.token
        }
    }
    return $payload
}

function Get-EntitlementsCacheSignature {
    $parts = @()
    foreach ($modName in (Get-BetaEntitlementsMap).Keys | Sort-Object) {
        $record = Get-BetaEntitlement $modName
        if (-not $record) { continue }
        $expired = if (Test-EntitlementExpired $record) { "expired" } else { "active" }
        $token = if ($record.token) { [string]$record.token } else { "" }
        $parts += "$modName@$token@$expired"
    }
    return Get-HashHex (($parts -join ";") + "|$($script:VERSION)")
}

function Convert-BetaReasonText {
    param([string]$Reason)
    switch ($Reason) {
        "missing_token" { return "缺少该模组的测试资格。" }
        "expired" { return "该模组测试资格已过期。" }
        "invalid_signature" { return "该模组测试资格已失效，需要重新输入测试码。" }
        "mod_mismatch" { return "测试资格与模组不匹配，请重新输入正确的测试码。" }
        "not_in_beta_catalog" { return "该模组当前没有可用的测试版分发。" }
        "malformed" { return "测试资格数据损坏，请重新输入测试码。" }
        default {
            if ($Reason) { return "测试资格不可用：$Reason" }
            return "测试资格不可用。"
        }
    }
}

function Get-BetaEntitlementList {
    $rows = @()
    foreach ($modName in (Get-BetaEntitlementsMap).Keys | Sort-Object) {
        $record = Get-BetaEntitlement $modName
        $status = if (Test-EntitlementExpired $record) { "已过期" } else { "有效" }
        $rows += [pscustomobject]@{
            Name = $modName
            ExpiresAt = if ($record -and $record.expires_at) { [string]$record.expires_at } else { "" }
            Status = $status
        }
    }
    return $rows
}

function Get-BetaEntitlementTableRows {
    $rows = @()
    $installedStates = @{}
    $gameDir = Get-GameDir
    if ($gameDir) {
        try { $installedStates = Get-InstalledModStates $gameDir } catch {}
    }

    foreach ($item in @(Get-BetaEntitlementList)) {
        $modName = [string]$item.Name
        $installed = if ($installedStates.ContainsKey($modName)) { $installedStates[$modName] } else { $null }
        $installedVer = if ($installed) { [string]$installed.LocalVer } else { "" }
        $installedChannel = if ($installed) { [string]$installed.Channel } else { "stable" }
        $expiresAt = if ($item.ExpiresAt) { [string]$item.ExpiresAt } else { "-" }

        if ($item.Status -eq "已过期") {
            $rows += (New-MenuEntry -Name $modName -Version "" -Channel "beta" -InstalledChannel $installedChannel -InstalledVersion $installedVer -ActionKind "menu_entitlement_expired" -Notice "【已过期】资格已失效，原到期时间: $expiresAt")
        } else {
            $rows += (New-MenuEntry -Name $modName -Version "" -Channel "beta" -InstalledChannel $installedChannel -InstalledVersion $installedVer -ActionKind "menu_entitlement" -Notice "【有效】资格有效期至: $expiresAt")
        }
    }

    return $rows
}

# ── 更新缓存（12h 冷却，减少重复请求）──
function Get-UpdateCache {
    if (-not (Test-Path $script:CACHE_FILE)) { return $null }
    try {
        $raw = Get-Content $script:CACHE_FILE -Raw -Encoding UTF8
        $cache = $raw | ConvertFrom-Json
        if (-not $cache.cache_version -or $cache.cache_version -ne $script:UPDATE_CACHE_VERSION) { return $null }
        if (-not $cache.entitlements_hash -or [string]$cache.entitlements_hash -ne (Get-EntitlementsCacheSignature)) { return $null }
        $lastCheck = [datetime]::Parse($cache.last_check_at)
        if (((Get-Date) - $lastCheck).TotalHours -ge $script:CHECK_TTL_HOURS) { return $null }
        return $cache.check_result
    } catch {
        Remove-Item $script:CACHE_FILE -Force -ErrorAction SilentlyContinue
        return $null
    }
}

function Save-UpdateCache($result) {
    try {
        @{
            cache_version = $script:UPDATE_CACHE_VERSION
            last_check_at = (Get-Date).ToString("o")
            entitlements_hash = Get-EntitlementsCacheSignature
            check_result = $result
        } | ConvertTo-Json -Depth 8 | Set-Content $script:CACHE_FILE -Encoding UTF8
    } catch {}
}

function Compare-VersionValue {
    param([string]$Left, [string]$Right)
    if ($Left -eq $Right) { return 0 }
    if (-not $Left) { return -1 }
    if (-not $Right) { return 1 }
    try {
        return ([version]$Left).CompareTo([version]$Right)
    } catch {
        return [string]::CompareOrdinal([string]$Left, [string]$Right)
    }
}

function Test-VersionGreaterThan {
    param([string]$Left, [string]$Right)
    return ((Compare-VersionValue $Left $Right) -gt 0)
}

function Test-VersionGreaterOrEqual {
    param([string]$Left, [string]$Right)
    return ((Compare-VersionValue $Left $Right) -ge 0)
}

function Get-ResponseMap {
    param($Object)
    $map = @{}
    if (-not $Object) { return $map }
    foreach ($prop in $Object.PSObject.Properties) {
        $map[[string]$prop.Name] = ConvertTo-HashtableDeep $prop.Value
    }
    return $map
}

function Get-CatalogMods {
    param($Response)
    if ($Response -and $Response.mods) {
        return Get-ResponseMap $Response.mods
    }
    return @{}
}

function Get-DefaultRemoteFilename {
    param([string]$ModName, [string]$Version, [string]$Channel)
    if ($Channel -eq "beta") {
        return "${ModName}_beta_v${Version}.zip"
    }
    return "${ModName}_v${Version}.zip"
}

function Get-StatusTag {
    param([string]$Channel, [bool]$HasLocal)
    if ($Channel -eq "beta" -and -not $HasLocal) { return "测试可安装" }
    if ($Channel -eq "beta") { return "测试" }
    return "正式"
}

function New-UpdateEntry {
    param(
        [string]$Name,
        [string]$CloudName,
        [string]$LocalName,
        [string]$LocalVer,
        [string]$RemoteVer,
        [string]$InstallDir,
        [string]$TargetChannel,
        [string]$InstalledChannel,
        [string]$ActionKind,
        [bool]$HasLocal,
        [string]$Notice = "",
        [string]$Token = "",
        [string]$Changelog = "",
        $ChangelogDetail = $null,
        [string]$UpdatedAt = ""
    )

    return @{
        Name = $Name
        LocalName = $LocalName
        CloudName = $CloudName
        LocalVer = $LocalVer
        RemoteVer = $RemoteVer
        InstallDir = $InstallDir
        TargetChannel = $TargetChannel
        InstalledChannel = $InstalledChannel
        ActionKind = $ActionKind
        HasLocal = $HasLocal
        StatusTag = Get-StatusTag -Channel $TargetChannel -HasLocal $HasLocal
        Notice = $Notice
        Token = $Token
        Changelog = $Changelog
        ChangelogDetail = $ChangelogDetail
        UpdatedAt = $UpdatedAt
        Filename = Get-DefaultRemoteFilename -ModName $Name -Version $RemoteVer -Channel $TargetChannel
    }
}

function Set-EntryDownloadSources($entry, $remote) {
    if ($remote.download_cn)   { $entry.DownloadCn   = [string]$remote.download_cn }
    if ($remote.download_intl) { $entry.DownloadIntl  = [string]$remote.download_intl }
    if ($remote.sha256)        { $entry.Sha256        = [string]$remote.sha256 }
}

function New-AttentionEntry {
    param(
        [string]$Name,
        [string]$CloudName,
        [string]$LocalName,
        [string]$LocalVer,
        [string]$Message,
        [string]$RemoteVer = "",
        [string]$UpdatedAt = "",
        [string]$Changelog = "",
        $ChangelogDetail = $null
    )

    return @{
        Name = $Name
        LocalName = $LocalName
        CloudName = $CloudName
        LocalVer = $LocalVer
        RemoteVer = $RemoteVer
        InstallDir = ""
        TargetChannel = ""
        InstalledChannel = ""
        ActionKind = "attention"
        HasLocal = [bool]$LocalVer
        StatusTag = "注意"
        Notice = $Message
        Token = ""
        Changelog = $Changelog
        ChangelogDetail = $ChangelogDetail
        UpdatedAt = $UpdatedAt
        Filename = ""
    }
}

function Format-VersionText {
    param([string]$Version, [bool]$IsLocal = $false)
    if (-not $Version) {
        return $(if ($IsLocal) { "未安装" } else { "-" })
    }
    return "v$Version"
}

function Get-EntryDisplayName {
    param($Entry)
    $tag = if ($Entry.StatusTag) { "[$($Entry.StatusTag)] " } else { "" }
    return "$tag$($Entry.CloudName)"
}

function Get-FallbackModMetadata {
    param([string]$ModName)
    if ($ModName -and $script:MOD_TABLE_METADATA.ContainsKey($ModName)) {
        return $script:MOD_TABLE_METADATA[$ModName]
    }
    return @{
        ChineseName = if ($ModName) { $ModName } else { "-" }
        Author = "-"
        CoopAllInstall = $false
    }
}

function Apply-EntryMetadata {
    param($Entry)
    if (-not $Entry) { return $Entry }

    $meta = Get-FallbackModMetadata $Entry.Name
    $Entry.ChineseName = [string]$meta.ChineseName
    $Entry.Author = [string]$meta.Author
    $Entry.CoopAllInstall = [bool]$meta.CoopAllInstall
    return $Entry
}

function Get-EntryChineseName {
    param($Entry)
    if ($Entry -and $Entry.ChineseName) { return [string]$Entry.ChineseName }
    if ($Entry -and $Entry.CloudName) { return [string]$Entry.CloudName }
    return "-"
}

function Get-EntryAuthor {
    param($Entry)
    if ($Entry -and $Entry.Author) { return [string]$Entry.Author }
    return "-"
}

function Get-EntryCoopLabel {
    param($Entry)
    if (-not $Entry -or $Entry.Name -eq "beta-service") { return "-" }
    return $(if ($Entry.CoopAllInstall) { "是" } else { "否" })
}

function Get-EntryChannelLabel {
    param($Entry)
    if (-not $Entry -or $Entry.Name -eq "beta-service") { return "-" }
    if ($Entry.TargetChannel -eq "beta") { return "测试" }
    if ($Entry.ActionKind -eq "current" -and $Entry.InstalledChannel -eq "beta") { return "测试" }
    return "正式"
}

function Get-EntryVersionSummary {
    param($Entry)
    if (-not $Entry) { return "-" }

    $remoteText = Format-VersionText -Version $Entry.RemoteVer
    $localText = Format-VersionText -Version $Entry.LocalVer -IsLocal $true

    switch ([string]$Entry.ActionKind) {
        "menu_install" { return $remoteText }
        "menu_install_current" { return $remoteText }
        "menu_install_update" { return "$localText→$remoteText" }
        "menu_install_older" { return "$localText→$remoteText" }
        "menu_install_beta" { return "$localText→$remoteText" }
        "menu_uninstall" { return $localText }
        "menu_uninstall_beta" { return $localText }
        "menu_installed" { return $localText }
        "menu_installed_beta" { return $localText }
        "menu_entitlement" { return $(if ($Entry.LocalVer) { $localText } else { "-" }) }
        "menu_entitlement_expired" { return $(if ($Entry.LocalVer) { $localText } else { "-" }) }
        "attention" {
            if ($Entry.LocalVer -and $Entry.RemoteVer) { return "$localText→$remoteText" }
            if ($Entry.LocalVer) { return $localText }
            if ($Entry.RemoteVer) { return $remoteText }
            return "-"
        }
    }

    if ($Entry.ActionKind -eq "current") { return $remoteText }
    if ($Entry.LocalVer -and $Entry.RemoteVer -and (Compare-VersionValue $Entry.LocalVer $Entry.RemoteVer) -eq 0) {
        return $remoteText
    }
    if (-not $Entry.LocalVer) {
        return "未装→$remoteText"
    }
    return "$localText→$remoteText"
}

function Get-EntrySummaryText {
    param($Entry)
    if (-not $Entry) { return "-" }
    $badge = switch ([string]$Entry.ActionKind) {
        "install" { "【测试可装】" }
        "switch_to_beta" { "【切换测试】" }
        "promote_to_stable" { "【转正式版】" }
        "update" {
            if ((Get-EntryChannelLabel $Entry) -eq "测试") { "【测试更新】" } else { "【正式更新】" }
        }
        default { "" }
    }

    if ($Entry.ActionKind -eq "current") {
        $summary = if ($Entry.Changelog) { [string]$Entry.Changelog } elseif ($Entry.Notice) { [string]$Entry.Notice } else { "-" }
        if ($Entry.UpdatedAt) { $summary = "$summary ($($Entry.UpdatedAt))" }
        return $summary
    }

    switch ([string]$Entry.ActionKind) {
        "menu_install" { return [string]$Entry.Notice }
        "menu_install_current" { return [string]$Entry.Notice }
        "menu_install_update" { return [string]$Entry.Notice }
        "menu_install_older" { return [string]$Entry.Notice }
        "menu_install_beta" { return [string]$Entry.Notice }
        "menu_uninstall" { return [string]$Entry.Notice }
        "menu_uninstall_beta" { return [string]$Entry.Notice }
        "menu_installed" { return [string]$Entry.Notice }
        "menu_installed_beta" { return [string]$Entry.Notice }
        "menu_entitlement" { return [string]$Entry.Notice }
        "menu_entitlement_expired" { return [string]$Entry.Notice }
    }

    $summary = if ($Entry.Notice) { [string]$Entry.Notice } elseif ($Entry.Changelog) { [string]$Entry.Changelog } else { "-" }
    if ($Entry.UpdatedAt) { $summary = "$summary ($($Entry.UpdatedAt))" }
    if ($badge) { return "$badge $summary" }
    return $summary
}

function Get-EntryChannelColor {
    param($Entry, [bool]$IsCurrent = $false)
    $channel = Get-EntryChannelLabel $Entry
    switch ($channel) {
        "测试" { return "Magenta" }
        "正式" { return $(if ($IsCurrent) { "Cyan" } else { "Green" }) }
        default { return $(if ($IsCurrent) { "DarkGray" } else { "White" }) }
    }
}

function Get-EntryNoteColor {
    param($Entry, [bool]$IsCurrent = $false)
    if ($IsCurrent) { return "DarkGray" }

    switch ([string]$Entry.ActionKind) {
        "menu_install" { return "Green" }
        "menu_install_current" { return "DarkGray" }
        "menu_install_update" { return "Yellow" }
        "menu_install_older" { return "Red" }
        "menu_install_beta" { return "Magenta" }
        "menu_uninstall" { return "Yellow" }
        "menu_uninstall_beta" { return "Magenta" }
        "menu_installed" { return "Cyan" }
        "menu_installed_beta" { return "Magenta" }
        "menu_entitlement" { return "Green" }
        "menu_entitlement_expired" { return "Red" }
        "attention" {
            if ($Entry.Notice -match "过期|失效|不可用|损坏|失败") { return "Red" }
            return "Yellow"
        }
        "install" { return "Magenta" }
        "switch_to_beta" { return "Magenta" }
        "promote_to_stable" { return "Cyan" }
        "update" {
            if ((Get-EntryChannelLabel $Entry) -eq "测试") { return "Magenta" }
            return "Cyan"
        }
        default { return "Cyan" }
    }
}

function Get-EntryCoopColor {
    param($Entry, [bool]$IsCurrent = $false)
    if (-not $Entry -or $Entry.Name -eq "beta-service") { return $(if ($IsCurrent) { "DarkGray" } else { "White" }) }
    if ($Entry.CoopAllInstall) { return $(if ($IsCurrent) { "DarkRed" } else { "Red" }) }
    if ($IsCurrent) { return "DarkGray" }
    return "White"
}

function Write-UpdateTableDivider {
    param(
        $Widths,
        [string]$DefaultColor = "DarkGray",
        [string]$CoopColor = ""
    )

    if (-not $CoopColor) { $CoopColor = $DefaultColor }

    $segments = @(
        @{ Width = $Widths.Prefix; Color = $DefaultColor },
        @{ Width = $Widths.Id; Color = $DefaultColor },
        @{ Width = $Widths.Chinese; Color = $DefaultColor },
        @{ Width = $Widths.Author; Color = $DefaultColor },
        @{ Width = $Widths.Version; Color = $DefaultColor },
        @{ Width = $Widths.Channel; Color = $DefaultColor },
        @{ Width = $Widths.Coop; Color = $CoopColor },
        @{ Width = $Widths.Note; Color = $DefaultColor }
    )

    Write-Host "    " -NoNewline
    foreach ($segment in $segments) {
        Write-Host "+" -ForegroundColor $segment.Color -NoNewline
        Write-Host ("-" * ($segment.Width + 2)) -ForegroundColor $segment.Color -NoNewline
    }
    Write-Host "+" -ForegroundColor $DefaultColor
}

function Get-EntryPrimaryColor {
    param($Entry, [bool]$IsCurrent = $false)
    if ($IsCurrent) { return "DarkGray" }

    switch ([string]$Entry.ActionKind) {
        "menu_install_current" { return "DarkGray" }
        "menu_installed" { return "White" }
        "menu_installed_beta" { return "White" }
        "attention" { return "White" }
        default { return "White" }
    }
}

function Get-EntryVersionColor {
    param($Entry, [bool]$IsCurrent = $false)
    if ($IsCurrent) { return "DarkGray" }

    switch ([string]$Entry.ActionKind) {
        "menu_install" { return "Green" }
        "menu_install_current" { return "DarkGray" }
        "menu_install_update" { return "Yellow" }
        "menu_install_older" { return "Red" }
        "menu_install_beta" { return "Magenta" }
        "menu_uninstall" { return "White" }
        "menu_uninstall_beta" { return "Magenta" }
        "menu_installed" { return "White" }
        "menu_installed_beta" { return "Magenta" }
        "menu_entitlement" { return $(if ($Entry.InstalledChannel -eq "beta") { "Magenta" } else { "White" }) }
        "menu_entitlement_expired" { return $(if ($Entry.InstalledChannel -eq "beta") { "Magenta" } else { "DarkGray" }) }
        "attention" { return "Yellow" }
        default { return "Green" }
    }
}

function Get-ConsoleWidth {
    $candidates = @()

    try {
        $rawWidth = [int]$Host.UI.RawUI.WindowSize.Width
        if ($rawWidth -gt 0) { $candidates += $rawWidth }
    } catch {}

    try {
        $consoleWidth = [int][Console]::WindowWidth
        if ($consoleWidth -gt 0) { $candidates += $consoleWidth }
    } catch {}

    if ($candidates.Count -gt 0) {
        return ($candidates | Measure-Object -Minimum).Minimum
    }
    return 120
}

function Fit-TableCell {
    param([string]$Text, [int]$Width)
    $text = if ($Text) { [string]$Text } else { "-" }
    if ((Get-DisplayWidth $text) -le $Width) { return $text }
    if ($Width -le 3) { return (Truncate-ToWidth $text $Width) }
    return (Truncate-ToWidth $text ($Width - 3)) + "..."
}

function Get-NotePreviewText {
    param([string]$Text, [int]$MaxChars = 10)

    $value = if ($Text) { [string]$Text } else { "-" }
    $value = ($value -replace '\s+', ' ').Trim()
    if (-not $value) { return "-" }
    if ($value.Length -gt $MaxChars) {
        return $value.Substring(0, $MaxChars) + "..."
    }
    return $value
}

function Get-UpdateTableWidths {
    param($Rows)

    $widths = @{
        Id = 20
        Chinese = 14
        Author = 12
        Version = 14
        Channel = 4
        Coop = 11
        Note = 23
    }

    $mins = @{
        Id = 14
        Chinese = 8
        Author = 8
        Version = 12
        Note = 8
    }

    foreach ($row in @($Rows)) {
        $widths.Id = [Math]::Min(30, [Math]::Max($widths.Id, (Get-DisplayWidth ([string]$row.Name)) + 1))
        $widths.Chinese = [Math]::Min(20, [Math]::Max($widths.Chinese, (Get-DisplayWidth (Get-EntryChineseName $row)) + 1))
        $widths.Author = [Math]::Min(18, [Math]::Max($widths.Author, (Get-DisplayWidth (Get-EntryAuthor $row)) + 1))
        $widths.Version = [Math]::Min(20, [Math]::Max($widths.Version, (Get-DisplayWidth (Get-EntryVersionSummary $row)) + 1))
        $widths.Channel = [Math]::Max($widths.Channel, (Get-DisplayWidth (Get-EntryChannelLabel $row)) + 1)
        $widths.Coop = [Math]::Max($widths.Coop, (Get-DisplayWidth (Get-EntryCoopLabel $row)) + 1)
        $notePreview = Get-NotePreviewText (Get-EntrySummaryText $row)
        $widths.Note = [Math]::Min(23, [Math]::Max($widths.Note, (Get-DisplayWidth $notePreview) + 1))
    }

    $consoleWidth = Get-ConsoleWidth
    $usableWidth = $consoleWidth - 8
    if ($usableWidth -lt 40) { $usableWidth = $consoleWidth }

    $occupied = 2 + 4 + $widths.Id + 2 + $widths.Chinese + 2 + $widths.Author + 2 + $widths.Version + 2 + $widths.Channel + 2 + $widths.Coop + 2
    $available = $usableWidth - $occupied
    if ($available -lt $mins.Note) { $available = $mins.Note }
    if ($available -gt 23) { $available = 23 }
    $widths.Note = $available

    $total = $occupied + $widths.Note
    $shrinkOrder = @('Note', 'Id', 'Chinese', 'Author', 'Version')
    while ($total -gt $usableWidth) {
        $changed = $false
        foreach ($key in $shrinkOrder) {
            if ($widths[$key] -gt $mins[$key]) {
                $widths[$key] -= 1
                $total -= 1
                $changed = $true
                if ($total -le $usableWidth) { break }
            }
        }
        if (-not $changed) { break }
    }

    return $widths
}

function Write-UpdateTableHeader {
    param($Widths)

    Write-Host "    " -NoNewline
    Write-Padded "模组ID" $Widths.Id "DarkGray"
    Write-Host "  " -NoNewline
    Write-Padded "中文名" $Widths.Chinese "DarkGray"
    Write-Host "  " -NoNewline
    Write-Padded "作者" $Widths.Author "DarkGray"
    Write-Host "  " -NoNewline
    Write-Padded "版本" $Widths.Version "DarkGray"
    Write-Host "  " -NoNewline
    Write-Padded "通道" $Widths.Channel "DarkGray"
    Write-Host "  " -NoNewline
    Write-Padded "联机都要装?" $Widths.Coop "DarkGray"
    Write-Host "  " -NoNewline
    Write-Host "说明" -ForegroundColor DarkGray

    $sepLine = ("─" * $Widths.Id) + "  " + ("─" * $Widths.Chinese) + "  " + ("─" * $Widths.Author) + "  " + ("─" * $Widths.Version) + "  " + ("─" * $Widths.Channel) + "  " + ("─" * $Widths.Coop) + "  " + ("─" * $Widths.Note)
    Write-Host "    $sepLine" -ForegroundColor DarkGray
}

function Write-UpdateTableRow {
    param(
        [string]$Prefix,
        [string]$PrefixColor,
        $Entry,
        [bool]$IsCurrent,
        $Widths
    )

    $idText = Fit-TableCell ([string]$Entry.Name) $Widths.Id
    $zhText = Fit-TableCell (Get-EntryChineseName $Entry) $Widths.Chinese
    $authorText = Fit-TableCell (Get-EntryAuthor $Entry) $Widths.Author
    $versionText = Fit-TableCell (Get-EntryVersionSummary $Entry) $Widths.Version
    $channelText = Fit-TableCell (Get-EntryChannelLabel $Entry) $Widths.Channel
    $coopText = Fit-TableCell (Get-EntryCoopLabel $Entry) $Widths.Coop
    $noteText = Fit-TableCell (Get-NotePreviewText (Get-EntrySummaryText $Entry)) $Widths.Note

    $textColor = Get-EntryPrimaryColor -Entry $Entry -IsCurrent $IsCurrent
    $versionColor = Get-EntryVersionColor -Entry $Entry -IsCurrent $IsCurrent
    $channelColor = Get-EntryChannelColor -Entry $Entry -IsCurrent $IsCurrent
    $coopColor = Get-EntryCoopColor -Entry $Entry -IsCurrent $IsCurrent
    $noteColor = Get-EntryNoteColor -Entry $Entry -IsCurrent $IsCurrent

    Write-Host "  " -NoNewline
    Write-Host $Prefix -ForegroundColor $PrefixColor -NoNewline
    $prefixPad = 4 - (Get-DisplayWidth $Prefix)
    if ($prefixPad -gt 0) { Write-Host (" " * $prefixPad) -NoNewline }

    Write-Padded $idText $Widths.Id $textColor
    Write-Host "  " -NoNewline
    Write-Padded $zhText $Widths.Chinese $textColor
    Write-Host "  " -NoNewline
    Write-Padded $authorText $Widths.Author $(if ($IsCurrent) { "DarkGray" } else { "Gray" })
    Write-Host "  " -NoNewline
    Write-Padded $versionText $Widths.Version $versionColor
    Write-Host "  " -NoNewline
    Write-Padded $channelText $Widths.Channel $channelColor
    Write-Host "  " -NoNewline
    Write-Padded $coopText $Widths.Coop $coopColor
    Write-Host "  " -NoNewline
    Write-Host $noteText -ForegroundColor $noteColor
}

function Get-InstalledModStates {
    param([string]$gameDir)
    $mods = @{}

    foreach ($mod in @(Get-InstalledMods $gameDir)) {
        try {
            $installName = [string]$mod.Name
            $manifest = $mod.Manifest
            if (-not $installName -or -not $manifest -or -not $manifest.version) { continue }
            if (-not $mods.ContainsKey($installName)) {
                $mods[$installName] = @{
                    Name = $installName
                    LocalName = if ($manifest.name) { [string]$manifest.name } else { $installName }
                    LocalVer = [string]$manifest.version
                    Dir = [string]$mod.InstallDir
                    Channel = Get-InstalledChannel $installName
                    IsLoose = [bool]$mod.IsLoose
                    HasLooseDuplicate = [bool]$mod.HasLooseDuplicate
                }
            }
        } catch {}
    }
    return $mods
}

function Check-OnlineUpdate {
    param([string]$gameDir)
    $result = @{
        Error = $null
        BetaError = $null
        Updates = @()
        UpToDate = @()
        Attention = @()
        CheckTime = Get-Date -Format "MM-dd HH:mm"
    }

    $stableResp = $null
    $lastCatalogErr = ""
    $catalogUrls = @("$($script:COS_BASE)/versions.json", $script:GITEE_CATALOG)
    foreach ($catalogUrl in $catalogUrls) {
        try {
            $stableResp = Invoke-WithRetry -Uri $catalogUrl -TimeoutSec 8 -MaxRetries 1
            if ($stableResp -and $stableResp.mods) { break }
            $lastCatalogErr = "返回数据无效"
            $stableResp = $null
        } catch {
            $lastCatalogErr = "$(Get-WebErrorMessage $_)"
            $stableResp = $null
        }
    }
    if (-not $stableResp -or -not $stableResp.mods) {
        $msg = if ($lastCatalogErr) { $lastCatalogErr } else { "所有目录源均不可用" }
        if ($msg.Length -gt 60) { $msg = $msg.Substring(0, 57) + "..." }
        $result.Error = $msg
        return $result
    }

    $stableMods = Get-CatalogMods $stableResp
    $betaMods = @{}
    $invalidTokens = @{}
    $entitlementTokens = Get-EntitlementsPayload

    if ($entitlementTokens.Count -gt 0) {
        try {
            $betaPayload = @{ entitlements = $entitlementTokens } | ConvertTo-Json -Depth 6 -Compress
            $betaResp = Invoke-JsonPost -Uri "$($script:UPDATE_API)/check-beta" -Body $betaPayload -TimeoutSec 8 -MaxRetries 1
            $betaMods = Get-CatalogMods $betaResp
            if ($betaResp -and $betaResp.invalid_tokens) {
                $invalidTokens = Get-ResponseMap $betaResp.invalid_tokens
            }
        } catch {
            $msg = "$(Get-WebErrorMessage $_)"
            if ($msg.Length -gt 60) { $msg = $msg.Substring(0, 57) + "..." }
            $result.BetaError = $msg
        }
    }

    $installedMods = Get-InstalledModStates $gameDir
    $processed = @{}
    foreach ($modName in ($installedMods.Keys | Sort-Object)) {
        $installed = $installedMods[$modName]
        $localVer = [string]$installed.LocalVer
        $localName = [string]$installed.LocalName
        $installDir = [string]$installed.Dir
        $channel = [string]$installed.Channel
        $stableRemote = if ($stableMods.ContainsKey($modName)) { $stableMods[$modName] } else { $null }
        $betaRemote = if ($betaMods.ContainsKey($modName)) { $betaMods[$modName] } else { $null }
        $hasEntitlement = $entitlementTokens.ContainsKey($modName)
        $invalidReason = if ($invalidTokens.ContainsKey($modName)) { [string]$invalidTokens[$modName] } else { "" }

        if ($channel -eq "beta") {
            if ($betaRemote) {
                if (Test-VersionGreaterThan -Left ([string]$betaRemote.latest) -Right $localVer) {
                    $entry = New-UpdateEntry -Name $modName -CloudName $(if ($betaRemote.name) { [string]$betaRemote.name } else { $modName }) -LocalName $localName -LocalVer $localVer -RemoteVer ([string]$betaRemote.latest) -InstallDir $installDir -TargetChannel "beta" -InstalledChannel "beta" -ActionKind "update" -HasLocal $true -Notice "测试版有新版本可更新。" -Token $(if ($hasEntitlement) { [string]$entitlementTokens[$modName] } else { "" }) -Changelog $(if ($betaRemote.changelog) { [string]$betaRemote.changelog } else { "" }) -ChangelogDetail $betaRemote.changelog_detail -UpdatedAt $(if ($betaRemote.updated_at) { [string]$betaRemote.updated_at } else { "" })
                    $entry.Filename = $(if ($betaRemote.filename) { [string]$betaRemote.filename } else { Get-DefaultRemoteFilename -ModName $modName -Version ([string]$betaRemote.latest) -Channel "beta" })
                    Set-EntryDownloadSources $entry $betaRemote
                    $result.Updates += $entry
                } else {
                    $entry = New-UpdateEntry -Name $modName -CloudName $(if ($betaRemote.name) { [string]$betaRemote.name } else { $modName }) -LocalName $localName -LocalVer $localVer -RemoteVer ([string]$betaRemote.latest) -InstallDir $installDir -TargetChannel "beta" -InstalledChannel "beta" -ActionKind "current" -HasLocal $true -Notice $(if ($invalidReason) { Convert-BetaReasonText $invalidReason } else { "当前测试版已是最新。" }) -Token $(if ($hasEntitlement) { [string]$entitlementTokens[$modName] } else { "" }) -Changelog $(if ($betaRemote.changelog) { [string]$betaRemote.changelog } else { "" }) -ChangelogDetail $betaRemote.changelog_detail -UpdatedAt $(if ($betaRemote.updated_at) { [string]$betaRemote.updated_at } else { "" })
                    $entry.Filename = $(if ($betaRemote.filename) { [string]$betaRemote.filename } else { Get-DefaultRemoteFilename -ModName $modName -Version ([string]$betaRemote.latest) -Channel "beta" })
                    Set-EntryDownloadSources $entry $betaRemote
                    $result.UpToDate += $entry
                }
            } elseif ($stableRemote) {
                $stableVersion = [string]$stableRemote.latest
                if (Test-VersionGreaterOrEqual -Left $stableVersion -Right $localVer) {
                    $notice = if ($invalidReason) { "测试资格已失效；该模组已有正式版可切换。" } else { "该测试模组已转为正式版。" }
                    $entry = New-UpdateEntry -Name $modName -CloudName $(if ($stableRemote.name) { [string]$stableRemote.name } else { $modName }) -LocalName $localName -LocalVer $localVer -RemoteVer $stableVersion -InstallDir $installDir -TargetChannel "stable" -InstalledChannel "beta" -ActionKind "promote_to_stable" -HasLocal $true -Notice $notice -Changelog $(if ($stableRemote.changelog) { [string]$stableRemote.changelog } else { "" }) -ChangelogDetail $stableRemote.changelog_detail -UpdatedAt $(if ($stableRemote.updated_at) { [string]$stableRemote.updated_at } else { "" })
                    $entry.Filename = $(if ($stableRemote.filename) { [string]$stableRemote.filename } else { Get-DefaultRemoteFilename -ModName $modName -Version $stableVersion -Channel "stable" })
                    Set-EntryDownloadSources $entry $stableRemote
                    $result.Updates += $entry
                } else {
                    $message = if ($invalidReason) { "$(Convert-BetaReasonText $invalidReason) 正式版尚未追平当前测试版。" } else { "当前测试版高于正式版，等待正式版追平。" }
                    $result.Attention += (New-AttentionEntry -Name $modName -CloudName $(if ($stableRemote.name) { [string]$stableRemote.name } else { $modName }) -LocalName $localName -LocalVer $localVer -RemoteVer $stableVersion -UpdatedAt $(if ($stableRemote.updated_at) { [string]$stableRemote.updated_at } else { "" }) -Changelog $(if ($stableRemote.changelog) { [string]$stableRemote.changelog } else { "" }) -ChangelogDetail $stableRemote.changelog_detail -Message $message)
                }
            } else {
                $message = if ($invalidReason) { Convert-BetaReasonText $invalidReason } else { "该测试模组当前不在可用目录中。" }
                $result.Attention += (New-AttentionEntry -Name $modName -CloudName $localName -LocalName $localName -LocalVer $localVer -Message $message)
            }
        } else {
            $handled = $false
            if ($hasEntitlement -and $betaRemote) {
                $betaVersion = [string]$betaRemote.latest
                if (Test-VersionGreaterThan -Left $betaVersion -Right $localVer) {
                    $entry = New-UpdateEntry -Name $modName -CloudName $(if ($betaRemote.name) { [string]$betaRemote.name } else { $modName }) -LocalName $localName -LocalVer $localVer -RemoteVer $betaVersion -InstallDir $installDir -TargetChannel "beta" -InstalledChannel "stable" -ActionKind "switch_to_beta" -HasLocal $true -Notice "已解锁测试版，可切换到测试版。" -Token ([string]$entitlementTokens[$modName]) -Changelog $(if ($betaRemote.changelog) { [string]$betaRemote.changelog } else { "" }) -ChangelogDetail $betaRemote.changelog_detail -UpdatedAt $(if ($betaRemote.updated_at) { [string]$betaRemote.updated_at } else { "" })
                    $entry.Filename = $(if ($betaRemote.filename) { [string]$betaRemote.filename } else { Get-DefaultRemoteFilename -ModName $modName -Version $betaVersion -Channel "beta" })
                    Set-EntryDownloadSources $entry $betaRemote
                    $result.Updates += $entry
                    $handled = $true
                }
            }
            if (-not $handled -and $stableRemote) {
                $stableVersion = [string]$stableRemote.latest
                if (Test-VersionGreaterThan -Left $stableVersion -Right $localVer) {
                    $entry = New-UpdateEntry -Name $modName -CloudName $(if ($stableRemote.name) { [string]$stableRemote.name } else { $modName }) -LocalName $localName -LocalVer $localVer -RemoteVer $stableVersion -InstallDir $installDir -TargetChannel "stable" -InstalledChannel "stable" -ActionKind "update" -HasLocal $true -Notice "正式版有新版本可更新。" -Changelog $(if ($stableRemote.changelog) { [string]$stableRemote.changelog } else { "" }) -ChangelogDetail $stableRemote.changelog_detail -UpdatedAt $(if ($stableRemote.updated_at) { [string]$stableRemote.updated_at } else { "" })
                    $entry.Filename = $(if ($stableRemote.filename) { [string]$stableRemote.filename } else { Get-DefaultRemoteFilename -ModName $modName -Version $stableVersion -Channel "stable" })
                    Set-EntryDownloadSources $entry $stableRemote
                    $result.Updates += $entry
                } else {
                    $entry = New-UpdateEntry -Name $modName -CloudName $(if ($stableRemote.name) { [string]$stableRemote.name } else { $modName }) -LocalName $localName -LocalVer $localVer -RemoteVer $stableVersion -InstallDir $installDir -TargetChannel "stable" -InstalledChannel "stable" -ActionKind "current" -HasLocal $true -Notice "正式版已是最新。" -Changelog $(if ($stableRemote.changelog) { [string]$stableRemote.changelog } else { "" }) -ChangelogDetail $stableRemote.changelog_detail -UpdatedAt $(if ($stableRemote.updated_at) { [string]$stableRemote.updated_at } else { "" })
                    $entry.Filename = $(if ($stableRemote.filename) { [string]$stableRemote.filename } else { Get-DefaultRemoteFilename -ModName $modName -Version $stableVersion -Channel "stable" })
                    Set-EntryDownloadSources $entry $stableRemote
                    $result.UpToDate += $entry
                }
            }
            if ($invalidReason) {
                $result.Attention += (New-AttentionEntry -Name $modName -CloudName $localName -LocalName $localName -LocalVer $localVer -Message (Convert-BetaReasonText $invalidReason))
            }
        }

        if ($installed.HasLooseDuplicate) {
            $result.Attention += (New-AttentionEntry -Name $modName -CloudName $localName -LocalName $localName -LocalVer $localVer -Message "检测到 mods 根目录同名 loose 文件；游戏当前以目录版为准。若继续通过模组管理器安装 / 更新 / 卸载该模组，脚本会自动清理这些根文件。")
        }

        $processed[$modName] = $true
    }

    foreach ($modName in ($entitlementTokens.Keys | Sort-Object)) {
        if ($processed.ContainsKey($modName)) { continue }
        $invalidReason = if ($invalidTokens.ContainsKey($modName)) { [string]$invalidTokens[$modName] } else { "" }
        if ($betaMods.ContainsKey($modName)) {
            $betaRemote = $betaMods[$modName]
            $installDir = Join-Path (Join-Path $gameDir "mods") $modName
            $entry = New-UpdateEntry -Name $modName -CloudName $(if ($betaRemote.name) { [string]$betaRemote.name } else { $modName }) -LocalName "" -LocalVer "" -RemoteVer ([string]$betaRemote.latest) -InstallDir $installDir -TargetChannel "beta" -InstalledChannel "stable" -ActionKind "install" -HasLocal $false -Notice "已解锁测试版，可直接下载安装。" -Token ([string]$entitlementTokens[$modName]) -Changelog $(if ($betaRemote.changelog) { [string]$betaRemote.changelog } else { "" }) -ChangelogDetail $betaRemote.changelog_detail -UpdatedAt $(if ($betaRemote.updated_at) { [string]$betaRemote.updated_at } else { "" })
            $entry.Filename = $(if ($betaRemote.filename) { [string]$betaRemote.filename } else { Get-DefaultRemoteFilename -ModName $modName -Version ([string]$betaRemote.latest) -Channel "beta" })
            Set-EntryDownloadSources $entry $betaRemote
            $result.Updates += $entry
        } elseif ($invalidReason) {
            $result.Attention += (New-AttentionEntry -Name $modName -CloudName $modName -LocalName "" -LocalVer "" -Message (Convert-BetaReasonText $invalidReason))
        } elseif (-not $result.BetaError) {
            $result.Attention += (New-AttentionEntry -Name $modName -CloudName $modName -LocalName "" -LocalVer "" -Message "测试码已录入，但云端暂未提供该模组测试版。")
        }
    }

    if ($result.BetaError) {
        $result.Attention += (New-AttentionEntry -Name "beta-service" -CloudName "测试版目录" -LocalName "" -LocalVer "" -Message "测试版检查失败: $($result.BetaError)")
    }

    return $result
}

function Update-SingleMod {
    param($updateItem)
    $modName = [string]$updateItem.Name
    $display = [string]$updateItem.CloudName
    $channel = if ($updateItem.TargetChannel) { [string]$updateItem.TargetChannel } else { "stable" }

    $tempZip = Join-Path $env:TEMP "sts2_update_$modName.zip"
    $tempExtract = Join-Path $env:TEMP "sts2_extract_$modName"
    $downloaded = $false
    $hashVerified = $false

    # ── 多源下载链：Gitee → GitHub → COS (SCF 签名URL) ──
    # 仅 stable 通道 + 有 SHA256 时才走直链（beta 始终走 SCF）
    $directUrls = @()
    if ($channel -eq "stable" -and $updateItem.Sha256) {
        if ($updateItem.DownloadCn)   { $directUrls += [string]$updateItem.DownloadCn }
        if ($updateItem.DownloadIntl) { $directUrls += [string]$updateItem.DownloadIntl }
    }

    foreach ($directUrl in $directUrls) {
        $host_ = ""
        try { $host_ = ([Uri]$directUrl).Host } catch { $host_ = "mirror" }
        try {
            Write-Info "[$display] 下载 $(Format-VersionText $updateItem.RemoteVer)..."
            Write-Dim "    下载源: $host_"
            Download-FileWithRetry -Uri $directUrl -OutFile $tempZip -TimeoutSec 15 -MaxRetries 0
            $size = [math]::Round((Get-Item $tempZip).Length / 1KB, 0)
            Write-Dim "    下载完成 (${size}KB)"

            # 直链下载后立即校验 SHA256 + 版本，失败则继续下一源
            if (-not (Test-FileSha256 -FilePath $tempZip -ExpectedHash ([string]$updateItem.Sha256))) {
                Write-Dim "    $host_ SHA256 不匹配，切换备用源..."
                Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
                continue
            }
            Write-Dim "    SHA256 校验通过"
            $downloaded = $true
            $hashVerified = $true
            break
        } catch {
            Write-Dim "    $host_ 不可用，切换备用源..."
            Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
        }
    }

    # 兜底：SCF 签名 URL（现有逻辑）
    if (-not $downloaded) {
        Write-Info "[$display] 获取下载链接..."
        try {
            $expectedVer = [uri]::EscapeDataString([string]$updateItem.RemoteVer)
            $query = "$($script:UPDATE_API)/download?mod=$([uri]::EscapeDataString($modName))&version=$expectedVer&channel=$channel"
            if ($channel -eq "beta") {
                if (-not $updateItem.Token) { throw "缺少测试版资格 token" }
                $query += "&token=$([uri]::EscapeDataString([string]$updateItem.Token))"
            }
            $resp = Invoke-WithRetry -Uri $query -TimeoutSec 8
        } catch {
            Write-Err "[$display] 获取下载链接失败: $(Get-WebErrorMessage $_)"
            return $false
        }
        $respVersion = if ($resp.version) { [string]$resp.version } else { "" }
        if ($respVersion -and $respVersion -ne [string]$updateItem.RemoteVer) {
            Write-Err "[$display] 下载服务仍返回旧版 v$respVersion（面板显示 v$($updateItem.RemoteVer)）。这通常是云函数 5 分钟缓存未刷新，请稍等 5 分钟后再试。"
            return $false
        }
        if (-not $resp.url) {
            Write-Err "[$display] 下载链接无效"
            return $false
        }

        Write-Info "[$display] 下载 $(Format-VersionText $updateItem.RemoteVer)..."
        try {
            $downloadUri = [Uri]$resp.url
            Write-Dim "    下载源: $($downloadUri.Host) (云端)"
        } catch {}
        try {
            Download-FileWithRetry -Uri $resp.url -OutFile $tempZip -TimeoutSec 120 -MaxRetries 1
            $size = [math]::Round((Get-Item $tempZip).Length / 1KB, 0)
            Write-Dim "    下载完成 (${size}KB)"
            $downloaded = $true
        } catch {
            Write-Err "[$display] 下载失败: $(Get-WebErrorMessage $_)"
            Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
            return $false
        }
    }

    # ── SHA256 校验（仅 SCF 路径需要，镜像路径已在循环内校验）──
    if ($updateItem.Sha256 -and -not $hashVerified) {
        if (-not (Test-FileSha256 -FilePath $tempZip -ExpectedHash ([string]$updateItem.Sha256))) {
            Write-Err "[$display] 文件校验失败（SHA256 不匹配），已丢弃下载文件。请稍后重试。"
            Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
            return $false
        }
        Write-Dim "    SHA256 校验通过"
    }

    # ── 版本鲜度守卫（防止镜像滞后覆盖正常安装）──
    # 探测逻辑与安装逻辑对齐：递归找 DLL → 取其所在目录的 manifest
    try {
        $probeDir = Join-Path $env:TEMP "sts2_probe_$modName"
        Remove-Item $probeDir -Recurse -Force -ErrorAction SilentlyContinue
        Expand-Archive -Path $tempZip -DestinationPath $probeDir -Force
        $probeDll = Get-ChildItem $probeDir -Filter "*.dll" -Recurse -File | Select-Object -First 1
        $probeManifestDir = if ($probeDll) { $probeDll.Directory.FullName } else { $probeDir }
        $probeManifest = Get-PreferredModManifest $probeManifestDir
        $probeVer = if ($probeManifest -and $probeManifest.version) { [string]$probeManifest.version } else { "" }
        Remove-Item $probeDir -Recurse -Force -ErrorAction SilentlyContinue
        if ($probeVer -and $probeVer -ne [string]$updateItem.RemoteVer) {
            Write-Err "[$display] 镜像包版本不匹配（期望 v$($updateItem.RemoteVer)，实际 v$probeVer），已丢弃。请稍后重试。"
            Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
            return $false
        }
    } catch {
        # 探测失败不阻塞安装（后续安装阶段有自己的版本校验）
        Remove-Item $probeDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Dim "    版本探测跳过: $($_.Exception.Message)"
    }

    Write-Info "[$display] 安装中..."
    try {
        Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
        Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

        $dllFiles = Get-ChildItem $tempExtract -Filter "*.dll" -Recurse -File
        if ($dllFiles.Count -eq 0) { throw "zip 中未找到 DLL 文件" }

        $sourceDir = $dllFiles[0].Directory.FullName
        $targetDir = [string]$updateItem.InstallDir
        if (-not $targetDir) { throw "缺少安装目标目录" }
        $modsRoot = Split-Path $targetDir -Parent
        if (-not (Remove-LooseModFiles $modsRoot $modName "清理旧的 loose 布局")) {
            throw "无法清理 mods 根目录下的 loose 文件，请关闭游戏后重试。"
        }
        if (-not (Test-Path $targetDir)) {
            New-Item $targetDir -ItemType Directory -Force | Out-Null
        }
        if (-not (Remove-LegacyExternalManifest $targetDir "清理旧的 legacy manifest")) {
            throw "无法清理旧的 mod_manifest.json，请关闭游戏后重试。"
        }
        Copy-Item "$sourceDir\*" -Destination $targetDir -Force -Recurse

        $installedManifest = Get-PreferredModManifest $targetDir
        $installedVer = if ($installedManifest -and $installedManifest.version) {
            [string]$installedManifest.version
        } else {
            ""
        }
        if ($installedVer -ne [string]$updateItem.RemoteVer) {
            $actualText = if ($installedVer) { "v$installedVer" } else { "缺少 manifest/version" }
            throw "安装后版本校验失败：期望 v$($updateItem.RemoteVer)，实际 $actualText。云端可能仍在下发旧包，请稍等 5 分钟后重试。"
        }

        if ($channel -eq "beta") {
            Set-InstalledChannel -ModName $modName -Channel "beta"
        } else {
            Set-InstalledChannel -ModName $modName -Channel "stable"
            if ($updateItem.ActionKind -eq "promote_to_stable") {
                Remove-BetaEntitlement -ModName $modName | Out-Null
            }
        }
        Save-Config
        Clear-UpdateCache

        if ($channel -ne "beta") {
            $localModDir = Join-Path $script:MODS_SOURCE $modName
            if (Test-Path $localModDir) {
                try {
                    Get-ChildItem $script:MODS_SOURCE -Directory -Filter "${modName}_v*" | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    $null = Remove-LegacyExternalManifest $localModDir "清理本地分发目录中的旧 legacy manifest"
                    Copy-Item "$sourceDir\*" -Destination $localModDir -Force -Recurse
                    Write-Dim "    分发包已同步"
                } catch {}
            } else {
                $versionedDir = Get-ChildItem $script:MODS_SOURCE -Directory -Filter "${modName}_v*" | Select-Object -First 1
                if ($versionedDir) {
                    try {
                        $newDir = Join-Path $script:MODS_SOURCE "${modName}_v$($updateItem.RemoteVer)"
                        Remove-Item $versionedDir.FullName -Recurse -Force
                        New-Item $newDir -ItemType Directory -Force | Out-Null
                        $null = Remove-LegacyExternalManifest $newDir "清理本地分发目录中的旧 legacy manifest"
                        Copy-Item "$sourceDir\*" -Destination $newDir -Force -Recurse
                        Write-Dim "    分发包已同步"
                    } catch {}
                }
            }
        } else {
            Write-Dim "    测试版不会回写本地离线分发包"
        }

        $localText = if ($updateItem.LocalVer) { "v$($updateItem.LocalVer)" } else { "未安装" }
        switch ($updateItem.ActionKind) {
            "install" { Write-Ok "[$display] 已安装测试版 v$($updateItem.RemoteVer)" }
            "switch_to_beta" { Write-Ok "[$display] $localText -> 测试版 v$($updateItem.RemoteVer) 切换成功" }
            "promote_to_stable" { Write-Ok "[$display] 已切换到正式版 v$($updateItem.RemoteVer)" }
            default { Write-Ok "[$display] $localText -> v$($updateItem.RemoteVer) 更新成功" }
        }
        return $true
    } catch {
        Write-Err "[$display] 安装失败: $($_.Exception.Message)"
        return $false
    } finally {
        Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
        Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ── 模组详情（完整更新日志）──
function Show-ModDetails {
    param($mods, $attention = @())
    Write-Host ""
    Write-Host "  ── 模组详情 ──" -ForegroundColor Cyan
    Write-Host ""

    $detailMods = @()
    foreach ($item in @($mods)) { $detailMods += (Apply-EntryMetadata -Entry $item) }
    $detailAttention = @()
    foreach ($item in @($attention)) { $detailAttention += (Apply-EntryMetadata -Entry $item) }

    foreach ($m in $detailMods) {
        $isUpdate = $m.ActionKind -ne "current"
        $nameColor = if ($isUpdate) { "Yellow" } else { "Green" }
        Write-Host "  $(Get-EntryDisplayName $m)" -ForegroundColor $nameColor

        Write-Dim "    中文名:    $(Get-EntryChineseName $m)"
        Write-Dim "    作者:      $(Get-EntryAuthor $m)"
        Write-Dim "    通道:      $(Get-EntryChannelLabel $m)"
        Write-Dim "    联机同装:  $(Get-EntryCoopLabel $m)"

        if ($m.LocalName -and $m.LocalName -ne $m.CloudName) {
            Write-Dim "    本地名称:  $($m.LocalName)"
        }

        Write-Host "    本地版本:  " -NoNewline -ForegroundColor DarkGray
        Write-Host (Format-VersionText -Version $m.LocalVer -IsLocal $true) -ForegroundColor White

        Write-Host "    云端版本:  " -NoNewline -ForegroundColor DarkGray
        $verColor = if ($isUpdate) { "Green" } else { "White" }
        Write-Host (Format-VersionText -Version $m.RemoteVer) -ForegroundColor $verColor

        if ($m.Notice) {
            Write-Dim "    状态说明:  $($m.Notice)"
        }

        if ($m.UpdatedAt) {
            Write-Dim "    发布日期:  $($m.UpdatedAt)"
        }

        if ($m.ChangelogDetail -and $m.ChangelogDetail.Count -gt 0) {
            Write-Dim "    更新日志:"
            foreach ($line in $m.ChangelogDetail) {
                Write-Host "      - $line" -ForegroundColor Cyan
            }
        } elseif ($m.Changelog) {
            Write-Host "    更新日志:  " -NoNewline -ForegroundColor DarkGray
            Write-Host "$($m.Changelog)" -ForegroundColor Cyan
        }

        Write-Host ""
    }

    if ($detailAttention -and $detailAttention.Count -gt 0) {
        Write-Host "  ── 需要留意 ──" -ForegroundColor Yellow
        Write-Host ""
        foreach ($m in $detailAttention) {
            Write-Host "  [$($m.StatusTag)] $($m.CloudName)" -ForegroundColor Yellow
            Write-Dim "    中文名:    $(Get-EntryChineseName $m)"
            Write-Dim "    作者:      $(Get-EntryAuthor $m)"
            Write-Dim "    联机同装:  $(Get-EntryCoopLabel $m)"
            Write-Dim "    $($m.Notice)"
            Write-Host ""
        }
    }
}

function Refresh-UpdateState {
    param([string]$gameDir, [bool]$UseCache = $false)
    $script:UsedCache = $false
    if ($UseCache) {
        $cached = Get-UpdateCache
        if ($cached) {
            $script:LastCheckResult = $cached
            $script:UsedCache = $true
            return $cached
        }
    }

    try {
        $script:LastCheckResult = Check-OnlineUpdate -gameDir $gameDir
    } catch {
        $script:LastCheckResult = @{
            Error = "网络异常"
            BetaError = $null
            Updates = @()
            UpToDate = @()
            Attention = @()
            CheckTime = Get-Date -Format "MM-dd HH:mm"
        }
    }
    if ($script:LastCheckResult) { Save-UpdateCache $script:LastCheckResult }
    return $script:LastCheckResult
}

# ── 显示更新面板（启动自动展示 + 手动触发共用）──
function Show-UpdatePanel {
    param(
        $checkResult,
        [string]$gameDir,
        [bool]$isStartup = $false,
        [bool]$fromCache = $false,
        [bool]$allowUpdateActions = $true
    )

    $updates = @()
    foreach ($item in @($checkResult.Updates)) { $updates += (Apply-EntryMetadata -Entry $item) }
    $upToDate = @()
    foreach ($item in @($checkResult.UpToDate)) { $upToDate += (Apply-EntryMetadata -Entry $item) }
    $attention = @()
    foreach ($item in @($checkResult.Attention)) { $attention += (Apply-EntryMetadata -Entry $item) }

    Write-Host ""

    if ($isStartup -and $env:STS2_SCRIPT_STATUS) {
        $bs = $env:STS2_SCRIPT_STATUS -split "\|"
        switch ($bs[0]) {
            "cloud" { Write-Ok "安装脚本已是最新 ($($bs[1]))" }
            "update" { Write-Ok "安装脚本已更新 $($bs[1]) -> $($bs[2]) ($($bs[3]))" }
            "skip" { Write-Dim "  已跳过脚本更新 (云端 $($bs[1]))" }
            "localnew" { Write-Dim "  本地脚本版本更新，保留本地版本 ($($bs[1]) > $($bs[2]))" }
            "fail" { Write-Warn "脚本同步失败: $($bs[1])，使用本地版本" }
            "dev" { Write-Host "  [DEV] 开发模式，使用本地脚本" -ForegroundColor Magenta }
        }
        $env:STS2_SCRIPT_STATUS = $null
    }

    $cacheTag = if ($fromCache) { " (缓存)" } else { "" }
    Write-Host "  ── 模组更新检查 ──" -ForegroundColor Cyan -NoNewline
    Write-Dim "                          $($checkResult.CheckTime)$cacheTag"
    Write-Host ""

    if ($checkResult.Error) {
        Write-Warn "连接更新服务器失败: $($checkResult.Error)"
        if (-not $isStartup) { Pause-AndReturn }
        return
    }

    $allMods = @()
    foreach ($m in $upToDate) { $allMods += $m }
    foreach ($m in $updates) { $allMods += $m }

    if ($allMods.Count -eq 0 -and $attention.Count -eq 0) {
        Write-Dim "  未检测到可追踪的在线模组"
        if (-not $isStartup) { Pause-AndReturn }
        return
    }

    if ($allMods.Count -gt 0) {
        $widths = Get-UpdateTableWidths -Rows $allMods
        Write-UpdateTableHeader -Widths $widths

        foreach ($m in $upToDate) {
            Write-UpdateTableRow -Prefix "[√]" -PrefixColor "Green" -Entry $m -IsCurrent $true -Widths $widths
        }

        for ($i = 0; $i -lt $updates.Count; $i++) {
            $m = $updates[$i]
            Write-UpdateTableRow -Prefix "$($i + 1)." -PrefixColor "Yellow" -Entry $m -IsCurrent $false -Widths $widths
        }
    }

    if ($attention.Count -gt 0) {
        Write-Host ""
        Write-Warn "以下模组/资格需要留意:"
        $attentionWidths = Get-UpdateTableWidths -Rows $attention
        Write-UpdateTableHeader -Widths $attentionWidths
        foreach ($m in $attention) {
            $prefixColor = if ($m.Notice -match "过期|失效|不可用|损坏|失败") { "Red" } else { "Yellow" }
            Write-UpdateTableRow -Prefix "!" -PrefixColor $prefixColor -Entry $m -IsCurrent $false -Widths $attentionWidths
        }
    }

    Write-Host ""

    if ($updates.Count -eq 0) {
        if ($allMods.Count -gt 0) {
            Write-Ok "所有已追踪模组已是最新状态"
            Write-Host ""
        }
        $choice = Read-Choice $(if ($allMods.Count -gt 0 -or $attention.Count -gt 0) { "按 D=查看详情 / Enter=回到主菜单: " } else { "按 Enter 回到主菜单: " })
        if ($choice -eq "D" -or $choice -eq "d") {
            Show-ModDetails -mods $allMods -attention $attention
            Pause-AndReturn
        } elseif (-not $isStartup) {
            # no-op, caller returns
        }
        return
    }

    if (-not $allowUpdateActions) {
        Write-Warn "启动阶段仅提示可安装/更新模组；如需处理，请进入主菜单后选择 6。"
        Write-Host ""
        $choice = Read-Choice "按 D=查看详情 / Enter=继续: "
        if ($choice -eq "D" -or $choice -eq "d") {
            Show-ModDetails -mods $allMods -attention $attention
            Pause-AndReturn
        }
        return
    }

    Write-Host "  [↑] 发现 $($updates.Count) 个模组可安装/更新" -ForegroundColor Yellow
    if ($attention.Count -gt 0) {
        Write-Host "  [!] 另有 $($attention.Count) 项资格/状态提醒" -ForegroundColor Yellow
    }
    Write-Host ""

    $prompt = if ($updates.Count -eq 1) {
        "按 1=处理 / D=详情 / Enter=跳过: "
    } else {
        "按 A=全部处理 / 1-$($updates.Count)=选择 / D=详情 / Enter=跳过: "
    }

    $choice = Read-Choice $prompt
    if ($choice -eq "" -or $choice -eq "0") { return }

    if ($choice -eq "D" -or $choice -eq "d") {
        Show-ModDetails -mods $allMods -attention $attention
        Pause-AndReturn
        return
    }

    $selection = @()
    if ($choice -eq "A" -or $choice -eq "a") {
        $selection = $updates
    } else {
        $num = 0
        if ([int]::TryParse($choice, [ref]$num) -and $num -ge 1 -and $num -le $updates.Count) {
            $selection = @($updates[$num - 1])
        } else {
            return
        }
    }

    Write-Host ""
    $success = 0
    $failed = 0
    foreach ($u in $selection) {
        if (Update-SingleMod $u) { $success++ } else { $failed++ }
    }

    if ($success -gt 0 -and $gameDir) {
        Write-Dim "正在刷新在线状态..."
        $null = Refresh-UpdateState -gameDir $gameDir -UseCache $false
    }

    Write-Host ""
    if ($failed -eq 0) {
        Write-Ok "处理完成 ($success 个模组)"
    } else {
        Write-Warn "处理完成: $success 成功, $failed 失败"
    }
    Pause-AndReturn
}

# ── 静默同步分发包 Mods/ 与游戏目录 ──
# 确保 (b) 不落后于 (a)，防止"安装模组"用旧版覆盖新版
function Sync-LocalMods {
    param([string]$gameDir)
    $modsDir = Join-Path $gameDir "mods"
    if (-not (Test-Path $modsDir) -or -not (Test-Path $script:MODS_SOURCE)) { return }

    foreach ($installedMod in @(Get-InstalledMods $gameDir)) {
        $manifest = $installedMod.Manifest
        $pck = [string]$installedMod.Name
        if (-not $manifest -or -not $pck -or -not $manifest.version) { continue }
        if ((Get-InstalledChannel $pck) -eq "beta") { continue }
        $installedVer = [string]$manifest.version

        $localDir = $null
        $localVer = $null
        foreach ($d in (Get-ChildItem $script:MODS_SOURCE -Directory -ErrorAction SilentlyContinue)) {
            if ($d.Name -eq $pck -or $d.Name -match "^${pck}_v") {
                $lm = Get-PreferredModManifest $d.FullName
                if ($lm) { $localDir = $d; $localVer = [string]$lm.version; break }
            }
        }
        if (-not $localDir -or -not $localVer) { continue }

        try {
            if (Test-VersionGreaterThan -Left $installedVer -Right $localVer) {
                $newDir = Join-Path $script:MODS_SOURCE "${pck}_v${installedVer}"
                Remove-Item $localDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
                New-Item $newDir -ItemType Directory -Force | Out-Null
                Copy-InstalledModContent $installedMod $newDir
            }
        } catch {}
    }
}

function Show-BetaEntitlementMenu {
    while ($true) {
        Clear-Host
        Write-Title "测试模组资格"

        $rows = @(Get-BetaEntitlementList)
        $tableRows = @(Get-BetaEntitlementTableRows)
        if ($rows.Count -eq 0) {
            Write-Dim "  当前没有已录入的测试模组资格。"
        } else {
            Write-Info "已录入测试资格:"
            Write-Host ""
            $widths = Get-UpdateTableWidths -Rows $tableRows
            Write-UpdateTableHeader -Widths $widths
            for ($i = 0; $i -lt $tableRows.Count; $i++) {
                $row = $tableRows[$i]
                $prefixColor = if ($row.ActionKind -eq "menu_entitlement_expired") { "Red" } else { "Green" }
                Write-UpdateTableRow -Prefix "$($i + 1)." -PrefixColor $prefixColor -Entry $row -IsCurrent $false -Widths $widths
            }
        }
        Write-Host ""
        Write-Host "    1. 输入测试码"
        Write-Host "    2. 查看已解锁测试模组"
        Write-Host "    3. 删除某个测试模组资格"
        Write-Host "    4. 清空全部测试资格"
        Write-Host "    0. 返回主菜单" -ForegroundColor DarkGray

        $choice = Read-Choice "请选择 [0-4]: "
        switch ($choice) {
            "1" {
                $code = Read-Choice "请输入测试码（直接回车取消）: "
                if (-not $code) { continue }
                try {
                    $payload = @{ code = $code } | ConvertTo-Json -Compress
                    $resp = Invoke-JsonPost -Uri "$($script:UPDATE_API)/redeem" -Body $payload -TimeoutSec 8 -MaxRetries 1
                    if (-not $resp -or -not $resp.ok -or -not $resp.mod -or -not $resp.token) {
                        throw "服务器返回数据无效"
                    }
                    Set-BetaEntitlement -ModName ([string]$resp.mod) -Record @{
                        token = [string]$resp.token
                        granted_at = if ($resp.granted_at) { [string]$resp.granted_at } else { "" }
                        expires_at = if ($resp.expires_at) { [string]$resp.expires_at } else { "" }
                    }
                    Save-Config
                    Clear-UpdateCache
                    Write-Ok "已解锁测试模组: $([string]$resp.name)"
                    if ($resp.expires_at) { Write-Dim "  资格有效期至: $([string]$resp.expires_at)" }

                    $dir = Get-GameDir
                    if ($dir) {
                        Write-Dim "正在刷新在线状态..."
                        $result = Refresh-UpdateState -gameDir $dir -UseCache $false
                        Show-UpdatePanel -checkResult $result -gameDir $dir -isStartup $false -fromCache $false -allowUpdateActions $true
                    } else {
                        Pause-AndReturn
                    }
                } catch {
                    $statusCode = Get-WebStatusCode $_
                    if ($statusCode -eq 403) {
                        Write-Err "测试码无效，或该测试版当前不可用。"
                    } elseif ($statusCode -eq 429) {
                        Write-Err "请求过于频繁，请稍后再试。"
                    } else {
                        Write-Err "兑换测试码失败: $(Get-WebErrorMessage $_)"
                    }
                    Pause-AndReturn
                }
            }
            "2" {
                if ($rows.Count -eq 0) {
                    Write-Info "暂无已解锁的测试模组。"
                } else {
                    Write-Host ""
                    foreach ($item in $rows) {
                        $exp = if ($item.ExpiresAt) { $item.ExpiresAt } else { "-" }
                        Write-Info "$($item.Name)  [$($item.Status)]  过期时间: $exp"
                    }
                }
                Pause-AndReturn
            }
            "3" {
                if ($rows.Count -eq 0) {
                    Write-Info "暂无可删除的测试资格。"
                    Pause-AndReturn
                    continue
                }
                $num = 0
                $pick = Read-Choice "输入要删除的编号 [1-$($rows.Count)]，直接回车取消: "
                if ([int]::TryParse($pick, [ref]$num) -and $num -ge 1 -and $num -le $rows.Count) {
                    $modName = [string]$rows[$num - 1].Name
                    if (Remove-BetaEntitlement -ModName $modName) {
                        Save-Config
                        Clear-UpdateCache
                        Write-Ok "已删除 $modName 的测试资格。"
                    }
                    Pause-AndReturn
                }
            }
            "4" {
                if ($rows.Count -eq 0) {
                    Write-Info "暂无测试资格需要清空。"
                    Pause-AndReturn
                    continue
                }
                $confirm = Read-Choice "确认清空全部测试资格？输入 Y 确认: "
                if ($confirm -ieq "Y") {
                    Clear-AllBetaEntitlements
                    Save-Config
                    Clear-UpdateCache
                    Write-Ok "已清空全部测试资格。"
                }
                Pause-AndReturn
            }
            "0" { return }
        }
    }
}

# ============================================================
#  主菜单
# ============================================================
function Show-MainMenu {
    Load-Config
    $script:LastCheckResult = $null

    try {
        $dir = Ensure-GameDir
    } catch {
        $dir = $null
        Write-Warn "游戏目录检测失败: $($_.Exception.Message)"
    }
    if ($dir) {
        $null = Get-BetaEntitlementsMap
        $null = Get-InstalledChannelsMap
        try { Sync-LocalMods -gameDir $dir } catch {}

        Write-Dim "正在检查模组更新..."
        $result = Refresh-UpdateState -gameDir $dir -UseCache $true

        try {
            Clear-Host
            Show-UpdatePanel -checkResult $result -gameDir $dir -isStartup $true -fromCache $script:UsedCache -allowUpdateActions $false
        } catch {
            Clear-Host
        }

        try { $null = Send-TelemetryReport -gameDir $dir } catch {}
    }

    while ($true) {
        Clear-Host
        Write-Host ""
        Show-MainMenuBanner
        Write-Host ""

        $dir = Get-GameDir
        if ($dir) {
            Write-Host "  [√] 游戏目录: $dir" -ForegroundColor Green
        } else {
            Write-Host "  [?] 游戏目录: 未设置" -ForegroundColor Yellow
        }

        if ($dir) {
            try {
                $instCount = (Get-InstalledMods $dir).Count
                $availCount = Get-InstallableMenuCount -gameDir $dir
                Write-Dim "      已安装 $instCount 个模组 | 可安装 $availCount 个模组"
            } catch {}
        }

        if ($script:LastCheckResult) {
            $cr = $script:LastCheckResult
            if ($cr.Error) {
                Write-Dim "      在线更新: 检查失败"
            } else {
                $pendingCount = @($cr.Updates).Count
                $attentionCount = @($cr.Attention).Count
                if ($pendingCount -gt 0) {
                    Write-Host "" 
                    Write-Host "  [↑] $pendingCount 个模组可安装/更新 (选 6 查看详情)" -ForegroundColor Yellow
                } elseif (($cr.UpToDate.Count + $pendingCount) -gt 0) {
                    Write-Host "  [√] 模组已是最新" -ForegroundColor Green -NoNewline
                    Write-Dim "  $($cr.CheckTime)"
                }
                if ($attentionCount -gt 0) {
                    Write-Host "  [!] $attentionCount 项测试资格/状态提醒 (选 6 查看详情)" -ForegroundColor Yellow
                }
            }
        }

        Write-Host ""
        Write-Host "    1. 安装模组" -ForegroundColor Cyan
        Write-Host "    2. 卸载模组"
        Write-Host "    3. 查看已安装模组"
        Write-Host "    4. 存档管理"
        Write-Host "    5. 设置"
        if ($script:LastCheckResult -and $script:LastCheckResult.Updates.Count -gt 0) {
            Write-Host "    6. 在线更新模组 ($($script:LastCheckResult.Updates.Count))" -ForegroundColor Yellow
        } else {
            Write-Host "    6. 检查在线更新"
        }
        Write-Host "    7. 测试模组资格"
        Write-Host "    0. 退出" -ForegroundColor DarkGray

        $choice = Read-Choice "请选择 [0-7]: "
        switch ($choice) {
            "1" { Install-Mod }
            "2" { Uninstall-Mod }
            "3" { Show-InstalledMods }
            "4" { Show-SaveMenu }
            "5" { Show-Settings }
            "6" {
                if ($dir) {
                    Write-Dim "正在检查模组更新..."
                    $result = Refresh-UpdateState -gameDir $dir -UseCache $false
                    try {
                        Show-UpdatePanel -checkResult $result -gameDir $dir -isStartup $false -fromCache $false
                    } catch {
                        Write-Err "显示更新面板失败: $($_.Exception.Message)"
                        Pause-AndReturn
                    }
                } else {
                    Write-Err "请先设置游戏目录"
                    Pause-AndReturn
                }
            }
            "7" { Show-BetaEntitlementMenu }
            "0" {
                Write-Host ""
                Write-Info "再见！祝你在尖塔中好运 :)"
                Write-Host ""
                return
            }
        }
    }
}

# ── 启动 ──
Initialize-ConsoleWindow
Start-Logging
try { Update-BootstrapIfNeeded } catch {}
try {
    Show-MainMenu
} catch {
    # 全局兜底：任何未捕获的异常都显示给用户而不是静默退出
    Write-Host ""
    Write-Host "  [!] 脚本遇到意外错误: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  如此问题持续出现，请截图以下信息反馈给 UP 主:" -ForegroundColor DarkGray
    Write-Host "  $($_.ScriptStackTrace)" -ForegroundColor DarkGray
    Write-Host ""
    if ($script:UseBasicConsoleOutput) {
        $null = Read-Host "  按回车继续"
        Write-Host ""
    } else {
        try {
            Write-Host "  按任意键继续..." -ForegroundColor DarkGray -NoNewline
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Write-Host ""
        } catch {
            $script:UseBasicConsoleOutput = $true
            $null = Read-Host "  按回车继续"
            Write-Host ""
        }
    }
} finally {
    Stop-Logging
}
