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
    $f.ClientSize = New-Object System.Drawing.Size(400, 150)
    $f.FormBorderStyle = 'None'
    $f.BackColor = [System.Drawing.Color]::White
    $f.TopMost = $true
    $f.ShowInTaskbar = $false
    $f.StartPosition = 'Manual'
    $f.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $f.Tag = $ev
    $btnOk = New-TextButton '知道了' $true 90 32 10
    $btnOk.Location = New-Object System.Drawing.Point(($f.ClientSize.Width - 20 - 110 - 10 - 90), ($f.ClientSize.Height - 20 - 32))
    $btnOk.Tag = $ev
    $btnSnooze = New-TextButton '稍后10分钟' $false 110 32 10
    $btnSnooze.Location = New-Object System.Drawing.Point(($f.ClientSize.Width - 20 - 110), ($f.ClientSize.Height - 20 - 32))
    $btnSnooze.Tag = $ev
    $f.Controls.AddRange(@($btnOk, $btnSnooze))

    # 圆角卡片 + 1px 描边，与主面板同风格（显示后按真实尺寸重算）
    $f.AutoScaleMode = 'None'
    $f.Add_Shown({ param($s, $e) Set-RoundedForm $s 10 })
    $f.Add_Resize({ param($s, $e) Set-RoundedForm $s 10 })
    $f.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $rmPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210, 210, 216), 1)
        $rmC = $sender.ClientRectangle
        $g.DrawRectangle($rmPen, $rmC.X, $rmC.Y, ($rmC.Width - 1), ($rmC.Height - 1))
        $rmPen.Dispose()
        if ($sender.Tag) {
            $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
            $evP = $sender.Tag
            $fTime = New-Object System.Drawing.Font('Microsoft YaHei UI', 11, [System.Drawing.FontStyle]::Bold)
            $bTime = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 120, 215))
            $g.DrawString("⏰ $($evP.time)", $fTime, $bTime, [single]20, [single]14)
            $fTitle = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
            $bTitle = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(45, 45, 55))
            $sfT = New-Object System.Drawing.StringFormat
            $sfT.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
            $sfT.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
            $g.DrawString($evP.title, $fTitle, $bTitle, (New-Object System.Drawing.RectangleF(20, 46, 360, 24)), $sfT)
            $fTime.Dispose(); $bTime.Dispose(); $fTitle.Dispose(); $bTitle.Dispose(); $sfT.Dispose()
        }
    })

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

