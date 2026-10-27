# TrayCal —— 右下角托盘日程日历（PowerShell 5.1 + WinForms，零依赖）
# M2：月历 + 日程增删改查 + 本地 JSON 存储 + 数据层 SelfTest
param(
    [switch]$SelfTest,
    [switch]$Show,       # 启动后自动弹出面板（用于截图自检/演示）
    [switch]$Demo,       # 截图自检：连"添加日程"对话框也自动打开
    [switch]$DemoReminder, # 截图自检：弹一条测试提醒窗
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

# ---------- 数据层（不依赖 GUI） ----------
function Get-NewEventId { [Guid]::NewGuid().ToString('N').Substring(0, 12) }

function Load-Events([string]$Path) {
    if (-not (Test-Path $Path)) { return @() }
    $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $j = $raw | ConvertFrom-Json
    if ($null -eq $j.events) { return @() }
    $list = @()
    foreach ($e in @($j.events)) {
        $t = $null
        if ($e.PSObject.Properties['time'] -and $e.time) { $t = [string]$e.time }
        $s = $null
        if ($e.PSObject.Properties['snoozeUntil'] -and $e.snoozeUntil) { $s = [string]$e.snoozeUntil }
        $r = $false
        if ($e.PSObject.Properties['reminded'] -and ($e.reminded -eq $true)) { $r = $true }
        $list += @{ id = [string]$e.id; title = [string]$e.title; date = [string]$e.date;
                    time = $t; reminded = $r; snoozeUntil = $s }
    }
    return $list
}

function Save-Events([string]$Path, $Events) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $json = @{ version = 1; events = @($Events) } | ConvertTo-Json -Depth 5
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -Path $tmp -Destination $Path -Force
}

function Get-EventDue([hashtable]$Ev) {
    if (-not $Ev.time) { return $null }
    return [DateTime]::ParseExact("$($Ev.date) $($Ev.time)", 'yyyy-MM-dd HH:mm', $null)
}

function Test-EventDueNow([hashtable]$Ev, [DateTime]$Now) {
    $due = Get-EventDue $Ev
    if ($null -eq $due) { return $false }
    if ($Ev.reminded) { return $false }
    if ($Now -lt $due) { return $false }
    if ($Ev.snoozeUntil) {
        $sn = [DateTime]::ParseExact($Ev.snoozeUntil, 'yyyy-MM-dd HH:mm:ss', $null)
        if ($Now -lt $sn) { return $false }
    }
    return $true
}

function Clear-StaleEvents($Events, [DateTime]$Now) {
    # 早已过期却未提醒的旧日程不补发
    foreach ($ev in $Events) {
        $due = Get-EventDue $ev
        if ($due -and $due -lt $Now -and -not $ev.reminded) { $ev.reminded = $true }
    }
    return $Events
}

function Get-WeekStart([DateTime]$d) {
    # 周一为一周之首
    $d = $d.Date
    $dow = (([int]$d.DayOfWeek) + 6) % 7
    return $d.AddDays(-$dow)
}

function Copy-WeekEvents($Events, [DateTime]$WeekStart, [int]$OffsetDays) {
    $end = $WeekStart.AddDays(6)
    $new = @()
    foreach ($ev in $Events) {
        $d = [DateTime]::ParseExact($ev.date, 'yyyy-MM-dd', $null)
        if ($d -ge $WeekStart -and $d -le $end) {
            $new += @{
                id          = Get-NewEventId
                title       = $ev.title
                date        = $d.AddDays($OffsetDays).ToString('yyyy-MM-dd')
                time        = $ev.time
                reminded    = $false
                snoozeUntil = $null
            }
        }
    }
    return $new
}

# ---------- SelfTest：数据层冒烟测试 ----------
if ($SelfTest) {
    $fail = 0
    function Assert($cond, $name) {
        if ($cond) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ }
    }
    $tmpFile = Join-Path $env:TEMP "traycal-selftest-$(Get-Random).json"
    try {
        $evs = @(
            @{ id = Get-NewEventId; title = '中文标题测试'; date = '2026-10-27'; time = '14:00'; reminded = $false; snoozeUntil = $null },
            @{ id = Get-NewEventId; title = '全天事项'; date = '2026-10-28'; time = $null; reminded = $false; snoozeUntil = $null }
        )
        Save-Events $tmpFile $evs
        $back = @(Load-Events $tmpFile)
        Assert ($back.Count -eq 2) '读写往返：条数一致'
        Assert ($back[0].title -eq '中文标题测试') '读写往返：中文标题无损'
        Assert ($null -eq $back[1].time) '读写往返：全天 time=null'
        Assert ($back[0].reminded -eq $false) '读写往返：reminded=false'
        Assert ((Get-EventDue $back[0]) -eq [DateTime]'2026-10-27 14:00') '到期计算：date+time 合成'
        Assert ($null -eq (Get-EventDue $back[1])) '到期计算：全天不提醒'
        Assert (Test-EventDueNow $back[0] ([DateTime]'2026-10-27 14:00:30')) '触发判定：到点应触发'
        Assert (-not (Test-EventDueNow $back[0] ([DateTime]'2026-10-27 13:59'))) '触发判定：未到不触发'
        function Copy-Ev($e) { @{ id = $e.id; title = $e.title; date = $e.date; time = $e.time; reminded = $e.reminded; snoozeUntil = $e.snoozeUntil } }
        $done = Copy-Ev $back[0]; $done.reminded = $true
        Assert (-not (Test-EventDueNow $done ([DateTime]'2026-10-27 15:00'))) '触发判定：已提醒不重复'
        $sn = Copy-Ev $back[0]; $sn.snoozeUntil = '2026-10-27 14:10:00'
        Assert (-not (Test-EventDueNow $sn ([DateTime]'2026-10-27 14:05'))) '触发判定：稍后期内不触发'
        Assert (Test-EventDueNow $sn ([DateTime]'2026-10-27 14:11')) '触发判定：稍后到期再触发'
        $stale = Copy-Ev $back[0]; $stale.reminded = $false; $stale.snoozeUntil = $null
        $cleared = @(Clear-StaleEvents @($stale) ([DateTime]'2026-10-28 09:00'))
        Assert ($cleared[0].reminded -eq $true) '陈旧事件：过期未提醒不补发'
        [System.IO.File]::WriteAllText($tmpFile, '{bad json', (New-Object System.Text.UTF8Encoding($false)))
        $err = $null
        try { Load-Events $tmpFile | Out-Null } catch { $err = 1 }
        Assert ($null -ne $err) '容错：损坏文件明确报错'
        Assert ((Get-WeekStart ([DateTime]'2026-10-27')) -eq [DateTime]'2026-10-26') '周计算：周二归到周一'
        Assert ((Get-WeekStart ([DateTime]'2026-10-26')) -eq [DateTime]'2026-10-26') '周计算：周一归到自己'
        $srcEvs = @(
            @{ id = 'x1'; title = '本周事项'; date = '2026-10-27'; time = '10:00'; reminded = $false; snoozeUntil = $null },
            @{ id = 'x2'; title = '下周事项'; date = '2026-11-03'; time = $null; reminded = $false; snoozeUntil = $null }
        )
        $copied = @(Copy-WeekEvents $srcEvs ([DateTime]'2026-10-26') 7)
        Assert ($copied.Count -eq 1) '复制周：只取本周范围内的日程'
        Assert ($copied[0].date -eq '2026-11-03') '复制周：日期平移+7天'
        Assert ($copied[0].id -ne 'x1') '复制周：生成新 id'
        Assert ($copied[0].reminded -eq $false) '复制周：重置提醒状态'
    } finally { Remove-Item $tmpFile -ErrorAction SilentlyContinue }
    if ($fail -eq 0) { Write-Host 'SelfTest 全部通过' -ForegroundColor Green; exit 0 }
    else { Write-Host "SelfTest 失败 $fail 项" -ForegroundColor Red; exit 1 }
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

# ---------- 托盘图标（优先 assets/note.png，缺失时 GDI+ 自绘兜底） ----------
function New-TrayIcon {
    $imgPath = Join-Path $AppDir 'assets\note.png'
    if (Test-Path $imgPath) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($imgPath)
            $ms = New-Object System.IO.MemoryStream(,$bytes)
            $src = New-Object System.Drawing.Bitmap($ms)
            $scaled = New-Object System.Drawing.Bitmap(32, 32)
            $g2 = [System.Drawing.Graphics]::FromImage($scaled)
            $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g2.DrawImage($src, 0, 0, 32, 32)
            $icon = [System.Drawing.Icon]::FromHandle($scaled.GetHicon())
            $src.Dispose(); $ms.Dispose(); $scaled.Dispose()
            return $icon
        } catch { Write-Log "note.png 转图标失败，改用自绘图标: $_" }
    }
    $bmp = New-Object System.Drawing.Bitmap(32, 32)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.FillRectangle([System.Drawing.Brushes]::White, 3, 5, 26, 24)
    $g.FillRectangle([System.Drawing.Brushes]::IndianRed, 3, 5, 26, 8)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(70, 70, 90), 2)
    $g.DrawRectangle($pen, 3, 5, 26, 24)
    $font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $rectF = New-Object System.Drawing.RectangleF(3, 12, 26, 17)
    $g.DrawString([string](Get-Date).Day, $font, [System.Drawing.Brushes]::Black, $rectF, $sf)
    $icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    $font.Dispose(); $pen.Dispose(); $g.Dispose(); $bmp.Dispose()
    return $icon
}

# ---------- 弹出面板控件 ----------
$panel = New-Object System.Windows.Forms.Form
$panel.FormBorderStyle = 'None'
$panel.BackColor = [System.Drawing.Color]::White
$panel.ControlBox = $false
$panel.ShowInTaskbar = $false
$panel.ShowIcon = $false
$panel.TopMost = $true
$panel.StartPosition = 'Manual'
$panel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

$mc = New-Object System.Windows.Forms.MonthCalendar
$mc.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 13)
$mc.FirstDayOfWeek = [System.Windows.Forms.Day]::Monday
$mc.ShowTodayCircle = $true
$panel.Controls.Add($mc) | Out-Null

$lblSel = New-Object System.Windows.Forms.Label
$lblSel.AutoSize = $true
$lblSel.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 70)
$panel.Controls.Add($lblSel) | Out-Null

$lv = New-Object System.Windows.Forms.ListView
$lv.View = 'Details'
$lv.FullRowSelect = $true
$lv.MultiSelect = $false
$lv.HideSelection = $false
$lv.HeaderStyle = 'None'
$lv.Columns.Add('时间', 58) | Out-Null
$lv.Columns.Add('日程', 292) | Out-Null
$panel.Controls.Add($lv) | Out-Null

function New-PanelButton($text, $accent) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Size = New-Object System.Drawing.Size(72, 28)
    $b.FlatStyle = 'Flat'
    if ($accent) {
        $b.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
        $b.ForeColor = [System.Drawing.Color]::White
        $b.FlatAppearance.BorderSize = 0
    }
    return $b
}
$btnAdd = New-PanelButton '添加日程' $true
$btnEdit = New-PanelButton '编辑' $false
$btnDel = New-PanelButton '删除' $false
$btnCopyWeek = New-PanelButton '复制本周→下周' $false
$btnCopyWeek.Size = New-Object System.Drawing.Size(120, 24)
$btnCopyWeek.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8)
$panel.Controls.AddRange(@($btnAdd, $btnEdit, $btnDel, $btnCopyWeek))

# 布局与圆角：控件句柄创建后月历真实尺寸才准，弹出时再校准
$pad = 16
$radius = 18

function Set-CardRegion {
    $c = $panel.ClientRectangle
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddArc($c.X, $c.Y, $radius, $radius, 180, 90)
    $p.AddArc($c.Right - $radius, $c.Y, $radius, $radius, 270, 90)
    $p.AddArc($c.Right - $radius, $c.Bottom - $radius, $radius, $radius, 0, 90)
    $p.AddArc($c.X, $c.Bottom - $radius, $radius, $radius, 90, 90)
    $p.CloseFigure()
    $old = $panel.Region
    $panel.Region = New-Object System.Drawing.Region($p)
    $p.Dispose()
    if ($old) { $old.Dispose() }
}

function Sync-PanelSize {
    if (-not $script:handleReady) { [void]$panel.Handle; [void]$mc.Handle; $script:handleReady = $true }
    # 面板宽度以"实测字宽×7列"为准，不信任控件报告的默认宽度（加粗与中文都可能更宽）
    $cellW = ([System.Windows.Forms.TextRenderer]::MeasureText('28', $mc.Font)).Width + 10
    $needW = $cellW * 7 + 24
    $w = [Math]::Max($mc.Width, $needW)
    $h = $mc.Height
    $mc.Size = New-Object System.Drawing.Size($w, $h)
    $lvH = 120
    $btnH = 32
    $panel.ClientSize = New-Object System.Drawing.Size(($w + $pad * 2), ($pad + $h + 34 + $lvH + 6 + $btnH + $pad))
    $mc.Location = New-Object System.Drawing.Point($pad, $pad)
    $lblSel.Location = New-Object System.Drawing.Point($pad, ($pad + $h + 7))
    $btnCopyWeek.Location = New-Object System.Drawing.Point(($pad + $w - 120), ($pad + $h + 3))
    $lv.Location = New-Object System.Drawing.Point($pad, ($pad + $h + 34))
    $lv.Size = New-Object System.Drawing.Size($w, $lvH)
    $by = ($pad + $h + 26 + $lvH + 6)
    $btnAdd.Size = New-Object System.Drawing.Size(86, $btnH)
    $btnAdd.Location = New-Object System.Drawing.Point($pad, $by)
    $rightX = ($panel.ClientSize.Width - $pad - 72)
    $editX  = [Math]::Max(($pad + 86 + 8), ($rightX - 8 - 72))
    $btnEdit.Size = New-Object System.Drawing.Size(72, $btnH)
    $btnDel.Size  = New-Object System.Drawing.Size(72, $btnH)
    $btnEdit.Location = New-Object System.Drawing.Point($editX, $by)
    $btnDel.Location  = New-Object System.Drawing.Point($rightX, $by)
    Set-CardRegion
    $panel.Invalidate()
}

$panel.Add_Paint({
    param($sender, $e)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210, 210, 216), 1)
    $c = $sender.ClientRectangle
    $e.Graphics.DrawRectangle($pen, $c.X, $c.Y, ($c.Width - 1), ($c.Height - 1))
    $pen.Dispose()
})

# ---------- 面板行为 ----------
function Refresh-Panel {
    $sel = $script:selectedDate
    $lblSel.Text = '{0}年{1}月{2}日 日程' -f $sel.Year, $sel.Month, $sel.Day
    $dayDates = @($script:events | ForEach-Object {
        try { [DateTime]::ParseExact($_.date, 'yyyy-MM-dd', $null) } catch { $null }
    } | Where-Object { $_ })
    if ($dayDates.Count -gt 0) { $mc.BoldedDates = [DateTime[]]$dayDates } else { $mc.BoldedDates = New-Object 'DateTime[]' 0 }
    # 加粗会改变月历实际宽度，内容更新后必须重新校准面板尺寸
    Sync-PanelSize
    $lv.Items.Clear()
    $dayEvents = @($script:events | Where-Object { $_.date -eq $sel.ToString('yyyy-MM-dd') } |
        Sort-Object { if ($_.time) { $_.time } else { '00:00' } })
    foreach ($e in $dayEvents) {
        $item = New-Object System.Windows.Forms.ListViewItem($(if ($e.time) { $e.time } else { '全天' }))
        $item.SubItems.Add($e.title) | Out-Null
        $item.Tag = $e.id
        if ($e.reminded -and $e.time) { $item.ForeColor = [System.Drawing.Color]::Gray }
        $lv.Items.Add($item) | Out-Null
    }
    $btnEdit.Enabled = ($lv.SelectedItems.Count -gt 0)
    $btnDel.Enabled = ($lv.SelectedItems.Count -gt 0)
}

function Show-Panel {
    if ($panel.Visible) { return }
    Refresh-Panel
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $panel.Location = New-Object System.Drawing.Point(($wa.Right - $panel.Width - 12), ($wa.Bottom - $panel.Height - 8))
    $panel.Show()
    $panel.Activate()
    $panel.BringToFront()
}
function Hide-Panel { $panel.Hide() }
function Toggle-Panel { if ($panel.Visible) { Hide-Panel } else { Show-Panel } }

$panel.Add_Deactivate({
    if (-not $script:suppressHide -and -not $KeepOpen -and $panel.Visible) { Hide-Panel }
})

$mc.Add_DateSelected({
    param($sender, $e)
    $script:selectedDate = $e.Start.Date
    Refresh-Panel
})

$lv.Add_SelectedIndexChanged({
    $btnEdit.Enabled = ($lv.SelectedItems.Count -gt 0)
    $btnDel.Enabled = ($lv.SelectedItems.Count -gt 0)
})

# ---------- 添加/编辑对话框 ----------
function Show-EditDialog([hashtable]$Existing, [DateTime]$DefaultDate) {
    $isNew = $null -eq $Existing
    $script:suppressHide = $true
    try {
        $dlg = New-Object System.Windows.Forms.Form
        $dlg.Text = $(if ($isNew) { '添加日程' } else { '编辑日程' })
        $dlg.ClientSize = New-Object System.Drawing.Size(340, 200)
        $dlg.FormBorderStyle = 'FixedDialog'
        $dlg.StartPosition = 'CenterScreen'
        $dlg.MinimizeBox = $false; $dlg.MaximizeBox = $false
        $dlg.ShowInTaskbar = $false; $dlg.ShowIcon = $false
        $dlg.TopMost = $true
        $dlg.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

        $lblT = New-Object System.Windows.Forms.Label; $lblT.Text = '标题'; $lblT.Location = '14,17'; $lblT.AutoSize = $true
        $txtT = New-Object System.Windows.Forms.TextBox; $txtT.Location = '70,14'; $txtT.Width = 256
        if (-not $isNew) { $txtT.Text = $Existing.title }

        $lblD = New-Object System.Windows.Forms.Label; $lblD.Text = '日期'; $lblD.Location = '14,49'; $lblD.AutoSize = $true
        $dtpD = New-Object System.Windows.Forms.DateTimePicker
        $dtpD.Location = '70,46'; $dtpD.Width = 150; $dtpD.Format = 'Short'
        if ($isNew) { $dtpD.Value = $DefaultDate.Date }
        else { $dtpD.Value = [DateTime]::ParseExact($Existing.date, 'yyyy-MM-dd', $null) }

        $lblH = New-Object System.Windows.Forms.Label; $lblH.Text = '时间'; $lblH.Location = '14,81'; $lblH.AutoSize = $true
        $dtpH = New-Object System.Windows.Forms.DateTimePicker
        $dtpH.Location = '70,78'; $dtpH.Width = 90; $dtpH.Format = 'Custom'
        $dtpH.CustomFormat = 'HH:mm'; $dtpH.ShowUpDown = $true
        if ($isNew) {
            if ($DefaultDate.Date -eq (Get-Date).Date) { $dtpH.Value = (Get-Date).AddMinutes(5) }
            else { $dtpH.Value = [DateTime]::Parse('2026-01-01 09:00') }
        } elseif ($Existing.time) {
            $dtpH.Value = [DateTime]::ParseExact("2026-01-01 $($Existing.time)", 'yyyy-MM-dd HH:mm', $null)
        } else {
            $dtpH.Value = [DateTime]::Parse('2026-01-01 09:00')
        }

        $chkAll = New-Object System.Windows.Forms.CheckBox
        $chkAll.Text = '全天（不提醒）'; $chkAll.Location = '170,78'; $chkAll.AutoSize = $true
        if ($isNew) { $chkAll.Checked = $false } else { $chkAll.Checked = (-not $Existing.time) }
        $dtpH.Enabled = -not $chkAll.Checked
        $chkAll.Add_CheckedChanged({ $dtpH.Enabled = -not $chkAll.Checked })

        $hint = New-Object System.Windows.Forms.Label
        $hint.Text = '定时日程到点弹提醒；全天只显示在列表。'
        $hint.Location = '14,110'; $hint.AutoSize = $true
        $hint.ForeColor = [System.Drawing.Color]::DimGray

        $btnOk = New-Object System.Windows.Forms.Button; $btnOk.Text = '保存'; $btnOk.Location = '90,148'; $btnOk.Size = '80,28'
        $btnCancel = New-Object System.Windows.Forms.Button; $btnCancel.Text = '取消'; $btnCancel.Location = '180,148'; $btnCancel.Size = '80,28'
        $btnOk.Add_Click({ $dlg.DialogResult = 'OK' })
        $btnCancel.Add_Click({ $dlg.DialogResult = 'Cancel' })
        $dlg.Controls.AddRange(@($lblT, $txtT, $lblD, $dtpD, $lblH, $dtpH, $chkAll, $hint, $btnOk, $btnCancel))
        $dlg.AcceptButton = $btnOk; $dlg.CancelButton = $btnCancel

        $result = $dlg.ShowDialog()
        $dlg.Dispose()
        if ($result -ne 'OK') { return }

        $title = $txtT.Text.Trim()
        if ($title -eq '') {
            [System.Windows.Forms.MessageBox]::Show('标题不能为空。', 'TrayCal', 'OK', 'Warning') | Out-Null
            return
        }
        $timeStr = $null
        if (-not $chkAll.Checked) { $timeStr = $dtpH.Value.ToString('HH:mm') }
        $dateStr = $dtpD.Value.ToString('yyyy-MM-dd')
        $now = Get-Date
        $due = $null
        if ($timeStr) { $due = [DateTime]::ParseExact("$dateStr $timeStr", 'yyyy-MM-dd HH:mm', $null) }
        $ev = @{
            id          = $(if ($isNew) { Get-NewEventId } else { $Existing.id })
            title       = $title
            date        = $dateStr
            time        = $timeStr
            reminded    = $(if ($due -and $due -lt $now) { $true } else { $false })
            snoozeUntil = $null
        }
        if ($isNew) { $script:events = @($script:events) + $ev }
        else { $script:events = @($script:events | ForEach-Object { if ($_.id -eq $ev.id) { $ev } else { $_ } }) }
        Save-Events $DataFile $script:events
        $script:selectedDate = [DateTime]::ParseExact($dateStr, 'yyyy-MM-dd', $null)
        $mc.SetDate($script:selectedDate)
        Refresh-Panel
    } finally {
        $script:suppressHide = $false
    }
}

$btnAdd.Add_Click({ Show-EditDialog $null $script:selectedDate })
$btnEdit.Add_Click({
    $ev = Get-SelectedEvent
    if ($ev) { Show-EditDialog $ev $script:selectedDate }
})
$btnDel.Add_Click({
    $ev = Get-SelectedEvent
    if (-not $ev) { return }
    $script:suppressHide = $true
    try {
        $r = [System.Windows.Forms.MessageBox]::Show("删除「$($ev.title)」？", 'TrayCal', 'YesNo', 'Question')
        if ($r -eq 'Yes') {
            $script:events = @($script:events | Where-Object { $_.id -ne $ev.id })
            Save-Events $DataFile $script:events
            Refresh-Panel
        }
    } finally { $script:suppressHide = $false }
})
$btnCopyWeek.Add_Click({
    $script:suppressHide = $true
    try {
        $ws = Get-WeekStart $script:selectedDate
        $we = $ws.AddDays(6)
        $cnt = @($script:events | Where-Object {
            $d = [DateTime]::ParseExact($_.date, 'yyyy-MM-dd', $null)
            $d -ge $ws -and $d -le $we
        }).Count
        if ($cnt -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("本周（$($ws.ToString('M月d日'))~$($we.ToString('M月d日'))）没有日程可复制。", 'TrayCal', 'OK', 'Information') | Out-Null
            return
        }
        $r = [System.Windows.Forms.MessageBox]::Show("把 $($ws.ToString('M月d日'))~$($we.ToString('M月d日')) 的 $cnt 条日程复制到下一周？`n`n（下周已有相同日程时会重复添加）", 'TrayCal', 'YesNo', 'Question')
        if ($r -ne 'Yes') { return }
        $newEvs = @(Copy-WeekEvents $script:events $ws 7)
        $script:events = @($script:events) + $newEvs
        Save-Events $DataFile $script:events
        Refresh-Panel
        [System.Windows.Forms.MessageBox]::Show("已复制 $($newEvs.Count) 条日程到 $($ws.AddDays(7).ToString('M月d日'))~$($we.AddDays(7).ToString('M月d日'))。", 'TrayCal', 'OK', 'Information') | Out-Null
    } catch {
        Write-Log "复制本周失败: $_"
        [System.Windows.Forms.MessageBox]::Show("复制失败：$($_.Exception.Message)", 'TrayCal', 'OK', 'Warning') | Out-Null
    } finally { $script:suppressHide = $false }
})

$lv.Add_MouseDoubleClick({
    $ev = Get-SelectedEvent
    if ($ev) { Show-EditDialog $ev $script:selectedDate }
})

function Get-SelectedEvent {
    if ($lv.SelectedItems.Count -eq 0) { return $null }
    $id = $lv.SelectedItems[0].Tag
    return ($script:events | Where-Object { $_.id -eq $id } | Select-Object -First 1)
}

# ---------- M3：到点提醒 ----------
$script:reminderForm = $null
$script:reminderQueue = @()

function Show-NextReminder {
    Write-Log "Show-NextReminder 进入 form=$($null -ne $script:reminderForm) queue=$($script:reminderQueue.Count)"
    if ($script:reminderForm -or $script:reminderQueue.Count -eq 0) { return }
    $ev = $script:reminderQueue[0]
    $script:reminderQueue = @($script:reminderQueue | Select-Object -Skip 1)

    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'TrayCal 提醒'
    $f.ClientSize = New-Object System.Drawing.Size(380, 120)
    $f.FormBorderStyle = 'FixedToolWindow'
    $f.TopMost = $true
    $f.ShowInTaskbar = $false
    $f.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "⏰ $($ev.time)  $($ev.title)"
    $lbl.Location = New-Object System.Drawing.Point(16, 18)
    $lbl.AutoSize = $true
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = '知道了'; $btnOk.Location = New-Object System.Drawing.Point(80, 60); $btnOk.Size = New-Object System.Drawing.Size(90, 30)
    $btnOk.Tag = $ev
    $btnSnooze = New-Object System.Windows.Forms.Button
    $btnSnooze.Text = '稍后10分钟'; $btnSnooze.Location = New-Object System.Drawing.Point(190, 60); $btnSnooze.Size = New-Object System.Drawing.Size(110, 30)
    $btnSnooze.Tag = $ev
    $f.Controls.AddRange(@($lbl, $btnOk, $btnSnooze))

    $btnOk.Add_Click({
        param($sender, $e)
        $ev2 = $sender.Tag
        $ev2.reminded = $true
        Save-Events $DataFile $script:events
        if ($script:panel.Visible) { Refresh-Panel }
        $script:reminderForm = $null; $sender.Parent.Close()
        Show-NextReminder
    })
    $btnSnooze.Add_Click({
        param($sender, $e)
        $ev2 = $sender.Tag
        $ev2.snoozeUntil = (Get-Date).AddMinutes(10).ToString('yyyy-MM-dd HH:mm:ss')
        Save-Events $DataFile $script:events
        $script:reminderForm = $null; $sender.Parent.Close()
        Show-NextReminder
    })
    $f.Add_FormClosed({ $script:reminderForm = $null })

    $script:reminderForm = $f
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $f.StartPosition = 'Manual'
    $f.Location = New-Object System.Drawing.Point(($wa.Right - $f.Width - 16), ($wa.Bottom - $f.Height - 60))
    [System.Media.SystemSounds]::Exclamation.Play()
    $f.Show()
    $f.Activate()
    Write-Log "提醒窗口已显示 $($f.Location)"
}

$uiTimer = New-Object System.Windows.Forms.Timer
$uiTimer.Interval = 20000
$uiTimer.Add_Tick({
    try {
        if ($script:reminderForm) { return }
        $now = Get-Date
        if ($script:reminderQueue.Count -eq 0) {
            $script:reminderQueue = @(foreach ($ev in $script:events) { if (Test-EventDueNow $ev $now) { $ev } })
        }
        if ($script:reminderQueue.Count -gt 0) { Show-NextReminder }
    } catch { Write-Log "提醒定时器异常: $_" }
})
$uiTimer.Start()

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
$miAuto   = $cm.Items.Add('开机自启')
$miExit   = $cm.Items.Add('退出')
$miToggle.Add_Click({ Toggle-Panel })
$miOpen.Add_Click({
    if (-not (Test-Path $DataFile)) { Save-Events $DataFile $script:events }
    Start-Process $DataFile
})
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
