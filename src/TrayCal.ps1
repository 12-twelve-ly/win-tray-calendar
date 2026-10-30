# TrayCal —— 右下角托盘日程日历（PowerShell 5.1 + WinForms，零依赖）
# M2：月历 + 日程增删改查 + 本地 JSON 存储 + 数据层 SelfTest
param(
    [switch]$SelfTest,
    [switch]$Show,       # 启动后自动弹出面板（用于截图自检/演示）
    [switch]$Demo,       # 截图自检：连"添加日程"对话框也自动打开
    [switch]$DemoReminder, # 截图自检：弹一条测试提醒窗
    [switch]$DemoCalMonth, # 截图自检：月历视图初始为月选择
    [switch]$DemoCalYear,  # 截图自检：月历视图初始为年选择
    [switch]$DemoBatchAdd, # 截图自检：打开批量添加对话框
    [switch]$DemoBatchDel, # 截图自检：打开批量删除对话框
    [switch]$DemoRange,    # 截图自检：预置一个日期选区
    [switch]$KeepOpen    # 调试：失去焦点不自动收起（配合截图用）
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$AppDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir  = Join-Path $AppDir 'data'
$DataFile = Join-Path $DataDir 'events.json'
$LogFile  = Join-Path $DataDir 'traycal.log'

function Write-Log($msg) {
    try {
        if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }
        $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
        [System.IO.File]::AppendAllText($LogFile, $line + "`r`n", (New-Object System.Text.UTF8Encoding($true)))
    } catch { }
}

# ---------- 模块加载（lib 与 tests 均相对本文件） ----------
. (Join-Path $PSScriptRoot 'lib\data.ps1')
. (Join-Path $PSScriptRoot 'lib\lunar.ps1')
if ($SelfTest) {
    $script:testExitCode = 0
    . (Join-Path $PSScriptRoot 'tests\SelfTest.ps1')
    exit $script:testExitCode
}
# ---------- 单实例 ----------
$mutex = New-Object System.Threading.Mutex($true, 'TrayCal_SingleInstance_Mutex')
if (-not $mutex.WaitOne(0)) {
    [System.Windows.Forms.MessageBox]::Show('TrayCal 已在运行（看右下角托盘图标）。', 'TrayCal', 'OK', 'Information') | Out-Null
    exit 0
}
[System.Windows.Forms.Application]::EnableVisualStyles()
# 全局 UI 异常兜底：记日志并友好提示，不再弹 .NET 崩溃窗
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({
    param($s, $e)
    Write-Log "UI异常: $($e.Exception.ToString())"
    [System.Windows.Forms.MessageBox]::Show("界面操作出现异常（已写入日志）：`n$($e.Exception.Message)", 'TrayCal', 'OK', 'Warning') | Out-Null
})

# ---------- 运行状态 ----------
$script:events = @()
$script:selectedDate = (Get-Date).Date
$script:viewMonth = New-Object DateTime((Get-Date).Year, (Get-Date).Month, 1)
$script:calMode = 'day'   # day | month | year
$script:rangeStart = $null
$script:rangeEnd = $null
$script:moveMode = $false
$script:moveEvId = $null
$script:eventDates = @{}
$script:suppressHide = $false
try { New-Item -ItemType Directory -Path $DataDir -ErrorAction SilentlyContinue | Out-Null } catch { }
try {
    $script:events = @(Clear-StaleEvents @(Load-Events $DataFile) (Get-Date))
} catch {
    Write-Log "数据文件加载失败: $_"
    if (Test-Path $DataFile) {
        $bak = "$DataFile.broken-$(Get-Date -Format yyyyMMddHHmmss)"
        Copy-Item $DataFile $bak -Force
        Write-Log "损坏数据已备份: $bak"
    }
    $script:events = @()
}

. (Join-Path $PSScriptRoot 'lib\ui-panel.ps1')
. (Join-Path $PSScriptRoot 'lib\ui-dialogs.ps1')
. (Join-Path $PSScriptRoot 'lib\ui-reminder.ps1')
# ---------- M3：开机自启（启动文件夹快捷方式 → vbs 静默拉起） ----------
function Get-AutostartLnk { Join-Path ([Environment]::GetFolderPath('Startup')) 'TrayCal.lnk' }
function Set-Autostart([bool]$Enable) {
    $lnk = Get-AutostartLnk
    if ($Enable) {
        $ws = New-Object -ComObject WScript.Shell
        $sc = $ws.CreateShortcut($lnk)
        $sc.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
        $sc.Arguments = '"' + (Join-Path $AppDir '启动TrayCal.vbs') + '"'
        $sc.WorkingDirectory = $AppDir
        $sc.Description = 'TrayCal 日程提醒'
        $sc.Save()
    } elseif (Test-Path $lnk) {
        Remove-Item $lnk -Force
    }
}

# ---------- 托盘与消息循环 ----------
$ni = New-Object System.Windows.Forms.NotifyIcon
$ni.Icon = New-TrayIcon
$ni.Text = 'TrayCal 日程'
$ni.Visible = $true

$cm = New-Object System.Windows.Forms.ContextMenuStrip
$miToggle = $cm.Items.Add('显示/隐藏日历')
$miOpen   = $cm.Items.Add('打开日程文件')
$miBatchAdd = $cm.Items.Add('批量添加…')
$miBatchDel = $cm.Items.Add('批量删除…')
$miAuto   = $cm.Items.Add('开机自启')
$miExit   = $cm.Items.Add('退出')
$miToggle.Add_Click({ Toggle-Panel })
$miOpen.Add_Click({
    if (-not (Test-Path $DataFile)) { Save-Events $DataFile $script:events }
    Start-Process $DataFile
})
$miBatchAdd.Add_Click({ Show-BatchAddDialog })
$miBatchDel.Add_Click({ Show-BatchDeleteDialog })
$miAuto.CheckOnClick = $true
$miAuto.Checked = Test-Path (Get-AutostartLnk)
$miAuto.Add_Click({ param($sender, $e) try { Set-Autostart $sender.Checked } catch { Write-Log "设置自启失败: $_" } })
$miExit.Add_Click({ [System.Windows.Forms.Application]::ExitThread() })
$ni.ContextMenuStrip = $cm

$ni.Add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Toggle-Panel }
})

Write-Log 'TrayCal M3 启动'

if ($Show -or $Demo) {
    $tShow = New-Object System.Windows.Forms.Timer
    $tShow.Interval = 600
    $tShow.Add_Tick({ $tShow.Stop(); $tShow.Dispose(); Show-Panel })
    $tShow.Start()
}
if ($Demo) {
    $tDemo = New-Object System.Windows.Forms.Timer
    $tDemo.Interval = 1500
    $tDemo.Add_Tick({ $tDemo.Stop(); $tDemo.Dispose(); Show-EditDialog $null $script:selectedDate })
    $tDemo.Start()
}
if ($DemoCalMonth) { $script:calMode = 'month' }
if ($DemoCalYear) { $script:calMode = 'year' }
if ($DemoRange) {
    $script:rangeStart = $script:viewMonth.AddDays(8)
    $script:rangeEnd = $script:viewMonth.AddDays(12)
    $script:selectedDate = $script:rangeEnd
}
if ($DemoBatchAdd) {
    $tBA = New-Object System.Windows.Forms.Timer
    $tBA.Interval = 900
    $tBA.Add_Tick({ $tBA.Stop(); $tBA.Dispose(); Show-BatchAddDialog })
    $tBA.Start()
}
if ($DemoBatchDel) {
    $tBD = New-Object System.Windows.Forms.Timer
    $tBD.Interval = 900
    $tBD.Add_Tick({ $tBD.Stop(); $tBD.Dispose(); Show-BatchDeleteDialog })
    $tBD.Start()
}
if ($DemoReminder) {
    $tR = New-Object System.Windows.Forms.Timer
    $tR.Interval = 900
    $tR.Add_Tick({
        $tR.Stop(); $tR.Dispose()
        $fake = @{ id = 'demo-reminder'; title = '【自检】提醒窗口测试'; date = (Get-Date).ToString('yyyy-MM-dd');
                   time = (Get-Date).ToString('HH:mm'); reminded = $false; snoozeUntil = $null }
        $script:reminderQueue = @($fake)
        Show-NextReminder
    })
    $tR.Start()
}

$ctx = New-Object System.Windows.Forms.ApplicationContext
[System.Windows.Forms.Application]::Run($ctx)

$ni.Visible = $false
$ni.Dispose()
$panel.Dispose()
$mutex.ReleaseMutex()
$mutex.Dispose()
Write-Log 'TrayCal 退出'
exit 0
