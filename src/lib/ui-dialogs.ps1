# ---------- 添加/编辑对话框 ----------
function Show-EditDialog([hashtable]$Existing, [DateTime]$DefaultDate) {
    $isNew = $null -eq $Existing
    $script:suppressHide = $true
    try {
        $dlg = New-Object System.Windows.Forms.Form
        $dlg.Text = $(if ($isNew) { '添加日程' } else { '编辑日程' })
        $dlg.ClientSize = New-Object System.Drawing.Size(400, 296)
        $dlg.FormBorderStyle = 'None'
        $dlg.BackColor = [System.Drawing.Color]::White
        $dlg.StartPosition = 'CenterScreen'
        $dlg.ShowInTaskbar = $false; $dlg.ShowIcon = $false
        $dlg.TopMost = $true
        $dlg.Font = New-Object System.Drawing.Font('Segoe UI', 9)

        # 文字标签改为在窗体 Paint 中 GDI+ 直绘（与主面板一致，不发虚）
        $txtT = New-Object System.Windows.Forms.TextBox; $txtT.Location = '80,60'; $txtT.Width = 296
        $txtT.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
        $txtT.BorderStyle = 'FixedSingle'
        if (-not $isNew) { $txtT.Text = $Existing.title }

        $dtpD = New-Object System.Windows.Forms.DateTimePicker
        $dtpD.Location = '80,104'; $dtpD.Width = 160; $dtpD.Format = 'Short'
        $dtpD.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
        if ($isNew) { $dtpD.Value = $DefaultDate.Date }
        else { $dtpD.Value = [DateTime]::ParseExact($Existing.date, 'yyyy-MM-dd', $null) }

        # 时/分两栏选择：小时 00-23 下拉，分钟 5 分钟一档下拉亦可手输
        $initTime = '09:00'
        if ($isNew) {
            if ($DefaultDate.Date -eq (Get-Date).Date) { $initTime = (Get-Date).AddMinutes(5).ToString('HH:mm') }
        } elseif ($Existing.time) { $initTime = $Existing.time }
        $initH = $initTime.Split(':')[0]
        $initM = $initTime.Split(':')[1]
        $cmbHour = New-Object System.Windows.Forms.ComboBox
        $cmbHour.Location = '80,148'; $cmbHour.Width = 62
        $cmbHour.DropDownStyle = 'DropDownList'
        $cmbHour.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
        for ($hh = 0; $hh -lt 24; $hh++) { $cmbHour.Items.Add(('{0:00}' -f $hh)) | Out-Null }
        $cmbHour.SelectedItem = ('{0:00}' -f [int]$initH)
        $cmbMin = New-Object System.Windows.Forms.ComboBox
        $cmbMin.Location = '156,148'; $cmbMin.Width = 62
        $cmbMin.DropDownStyle = 'DropDown'
        $cmbMin.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
        for ($mm = 0; $mm -lt 60; $mm += 5) { $cmbMin.Items.Add(('{0:00}' -f $mm)) | Out-Null }
        $cmbMin.Text = $initM

        $chkAll = New-Object System.Windows.Forms.CheckBox
        $chkAll.Text = ''; $chkAll.Location = '232,150'
        $chkAll.AutoSize = $false
        $chkAll.Size = New-Object System.Drawing.Size(20, 20)
        if ($isNew) { $chkAll.Checked = $false } else { $chkAll.Checked = (-not $Existing.time) }
        $cmbHour.Enabled = -not $chkAll.Checked
        $cmbMin.Enabled = -not $chkAll.Checked
        $chkAll.Add_CheckedChanged({ $cmbHour.Enabled = -not $chkAll.Checked; $cmbMin.Enabled = -not $chkAll.Checked })

        $btnOk = New-TextButton '保存' $true 84 32 10
        $btnOk.Location = New-Object System.Drawing.Point(198, 240)
        $btnCancel = New-TextButton '取消' $false 84 32 10
        $btnCancel.Location = New-Object System.Drawing.Point(292, 240)
        $btnClose = New-Object System.Windows.Forms.Button
        $btnClose.Text = '×'
        $btnClose.Size = New-Object System.Drawing.Size(32, 26)
        $btnClose.Location = New-Object System.Drawing.Point(352, 14)
        $btnClose.FlatStyle = 'Flat'
        $btnClose.FlatAppearance.BorderSize = 0
        $btnClose.BackColor = [System.Drawing.Color]::FromArgb(214, 69, 69)
        $btnClose.ForeColor = [System.Drawing.Color]::White
        $btnClose.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
        $btnClose.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(190, 52, 52)
        $btnClose.Add_Click({ $dlg.DialogResult = 'Cancel' })
        $btnOk.Add_Click({ $dlg.DialogResult = 'OK' })
        $btnCancel.Add_Click({ $dlg.DialogResult = 'Cancel' })
        $dlg.Controls.AddRange(@($btnClose, $txtT, $dtpD, $cmbHour, $cmbMin, $chkAll, $btnOk, $btnCancel))
        $dlg.AcceptButton = $btnOk; $dlg.CancelButton = $btnCancel

        # 圆角卡片 + 1px 描边（关闭自动缩放；显示后按真实尺寸重算圆角）
        $dlg.AutoScaleMode = 'None'
        $dlg.Add_Shown({ param($s, $e) Set-RoundedForm $s 10 })
        $dlg.Add_Resize({ param($s, $e) Set-RoundedForm $s 10 })
        $dlg.Add_Paint({
            param($sender, $e)
            $g = $e.Graphics
            $dlgPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210, 210, 216), 1)
            $dlgC = $sender.ClientRectangle
            $g.DrawRectangle($dlgPen, $dlgC.X, $dlgC.Y, ($dlgC.Width - 1), ($dlgC.Height - 1))
            $dlgPen.Dispose()
            $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
            $fHead = New-Object System.Drawing.Font('Microsoft YaHei UI', 12, [System.Drawing.FontStyle]::Bold)
            $bHead = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(35, 35, 45))
            $g.DrawString($sender.Text, $fHead, $bHead, [single]24, [single]18)
            $fHead.Dispose(); $bHead.Dispose()
            $fLbl = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
            $bLbl = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(90, 90, 100))
            $g.DrawString('标题', $fLbl, $bLbl, [single]24, [single]64)
            $g.DrawString('日期', $fLbl, $bLbl, [single]24, [single]108)
            $g.DrawString('时间', $fLbl, $bLbl, [single]24, [single]152)
            $g.DrawString(':', $fLbl, $bLbl, [single]145, [single]151)
            $g.DrawString('全天（不提醒）', $fLbl, $bLbl, [single]258, [single]152)
            $bLbl.Dispose(); $fLbl.Dispose()
            $fHint = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
            $bHint = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(135, 135, 145))
            $g.DrawString('定时日程到点弹提醒；全天只显示在列表。', $fHint, $bHint, [single]24, [single]190)
            $fHint.Dispose(); $bHint.Dispose()
        })

        $result = $dlg.ShowDialog()
        $dlg.Dispose()
        if ($result -ne 'OK') { return }

        $title = $txtT.Text.Trim()
        if ($title -eq '') {
            [System.Windows.Forms.MessageBox]::Show('标题不能为空。', 'TrayCal', 'OK', 'Warning') | Out-Null
            return
        }
        $timeStr = $null
        if (-not $chkAll.Checked) {
            $mv = $cmbMin.Text.Trim()
            if ($cmbHour.SelectedItem -and $mv -match '^\d{1,2}$' -and [int]$mv -ge 0 -and [int]$mv -le 59) {
                $timeStr = $cmbHour.SelectedItem.ToString() + ':' + ([int]$mv).ToString('00')
            } else {
                [System.Windows.Forms.MessageBox]::Show('分钟应为 0~59 的数字，例如 05。', 'TrayCal', 'OK', 'Warning') | Out-Null
                return
            }
        }
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
            sourceId    = $(if ($isNew) { $null } else { $Existing.sourceId })
        }
        if ($isNew) { $script:events = @($script:events) + $ev }
        else { $script:events = @($script:events | ForEach-Object { if ($_.id -eq $ev.id) { $ev } else { $_ } }) }
        Save-Events $DataFile $script:events
        $script:selectedDate = [DateTime]::ParseExact($dateStr, 'yyyy-MM-dd', $null)
        $script:viewMonth = New-Object DateTime($script:selectedDate.Year, $script:selectedDate.Month, 1)
        Refresh-Panel
    } finally {
        $script:suppressHide = $false
    }
}

# ---------- 批量添加/删除 ----------
function New-BatchDialogBase([string]$title, [int]$w, [int]$h) {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = $title
    $dlg.ClientSize = New-Object System.Drawing.Size($w, $h)
    $dlg.FormBorderStyle = 'None'
    $dlg.BackColor = [System.Drawing.Color]::White
    $dlg.StartPosition = 'CenterScreen'
    $dlg.ShowInTaskbar = $false; $dlg.ShowIcon = $false
    $dlg.TopMost = $true
    $dlg.AutoScaleMode = 'None'
    $dlg.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $dlg.Add_Shown({ param($s, $e) Set-RoundedForm $s 10 })
    $dlg.Add_Resize({ param($s, $e) Set-RoundedForm $s 10 })
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = '×'
    $btnClose.Size = New-Object System.Drawing.Size(32, 26)
    $btnClose.Location = New-Object System.Drawing.Point(($w - 48), 14)
    $btnClose.FlatStyle = 'Flat'
    $btnClose.FlatAppearance.BorderSize = 0
    $btnClose.BackColor = [System.Drawing.Color]::FromArgb(214, 69, 69)
    $btnClose.ForeColor = [System.Drawing.Color]::White
    $btnClose.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
    $btnClose.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(190, 52, 52)
    $btnClose.Add_Click({ $dlg.DialogResult = 'Cancel' })
    $dlg.Controls.Add($btnClose) | Out-Null
    $dlg.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210, 210, 216), 1)
        $c = $sender.ClientRectangle
        $g.DrawRectangle($pen, $c.X, $c.Y, ($c.Width - 1), ($c.Height - 1))
        $pen.Dispose()
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
        $fHead = New-Object System.Drawing.Font('Microsoft YaHei UI', 12, [System.Drawing.FontStyle]::Bold)
        $bHead = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(35, 35, 45))
        $g.DrawString($sender.Text, $fHead, $bHead, [single]24, [single]18)
        $fHead.Dispose(); $bHead.Dispose()
    })
    return $dlg
}

function Show-BatchAddDialog {
    $script:suppressHide = $true
    try {
        $dlg = New-BatchDialogBase '批量添加' 420 430
        $txtList = New-Object System.Windows.Forms.TextBox
        $txtList.Location = '24,80'; $txtList.Size = New-Object System.Drawing.Size(372, 66)
        $txtList.Multiline = $true
        $txtList.ScrollBars = 'Vertical'
        $txtList.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)

        $rsA = $script:rangeStart; $reA = $script:rangeEnd
        if (-not $rsA) { $rsA = $script:selectedDate; $reA = $script:selectedDate }
        if ($rsA -gt $reA) { $tA = $rsA; $rsA = $reA; $reA = $tA }
        $dtpFrom = New-Object System.Windows.Forms.DateTimePicker
        $dtpFrom.Location = '80,156'; $dtpFrom.Width = 120; $dtpFrom.Format = 'Short'
        $dtpFrom.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
        $dtpFrom.Value = $rsA.Date
        $dtpTo = New-Object System.Windows.Forms.DateTimePicker
        $dtpTo.Location = '224,156'; $dtpTo.Width = 120; $dtpTo.Format = 'Short'
        $dtpTo.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
        $dtpTo.Value = $reA.Date

        $cmbHour = New-Object System.Windows.Forms.ComboBox
        $cmbHour.Location = '80,196'; $cmbHour.Width = 56
        $cmbHour.DropDownStyle = 'DropDownList'
        $cmbHour.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
        for ($hh = 0; $hh -lt 24; $hh++) { $cmbHour.Items.Add(('{0:00}' -f $hh)) | Out-Null }
        $cmbHour.SelectedItem = '09'
        $cmbMin = New-Object System.Windows.Forms.ComboBox
        $cmbMin.Location = '152,196'; $cmbMin.Width = 56
        $cmbMin.DropDownStyle = 'DropDown'
        $cmbMin.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
        for ($mm = 0; $mm -lt 60; $mm += 5) { $cmbMin.Items.Add(('{0:00}' -f $mm)) | Out-Null }
        $cmbMin.Text = '00'
        $chkAll = New-Object System.Windows.Forms.CheckBox
        $chkAll.Text = ''; $chkAll.Location = '216,198'
        $chkAll.AutoSize = $false
        $chkAll.Size = New-Object System.Drawing.Size(20, 20)
        $chkAll.Add_CheckedChanged({ $cmbHour.Enabled = -not $chkAll.Checked; $cmbMin.Enabled = -not $chkAll.Checked })

        $btnOk = New-TextButton '保存' $true 84 32 10
        $btnOk.Location = New-Object System.Drawing.Point(198, 374)
        $btnCancel = New-TextButton '取消' $false 84 32 10
        $btnCancel.Location = New-Object System.Drawing.Point(292, 374)
        $btnOk.Add_Click({ $dlg.DialogResult = 'OK' })
        $btnCancel.Add_Click({ $dlg.DialogResult = 'Cancel' })
        $dlg.CancelButton = $btnCancel
        $dlg.Controls.AddRange(@($txtList, $dtpFrom, $dtpTo, $cmbHour, $cmbMin, $chkAll, $btnOk, $btnCancel))
        $dlg.Add_Paint({
            param($sender, $e)
            $g = $e.Graphics
            $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
            $fL = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
            $bL = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(90, 90, 100))
            $g.DrawString('标题（每行一条）', $fL, $bL, [single]24, [single]58)
            $g.DrawString('日期', $fL, $bL, [single]24, [single]160)
            $g.DrawString('至', $fL, $bL, [single]208, [single]160)
            $g.DrawString('时间', $fL, $bL, [single]24, [single]200)
            $g.DrawString(':', $fL, $bL, [single]141, [single]199)
            $g.DrawString('全天（不提醒）', $fL, $bL, [single]242, [single]200)
            $bL.Dispose(); $fL.Dispose()
            $fH = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
            $bH = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(135, 135, 145))
            $g.DrawString('每个标题 × 日期范围内的每一天各生成一条，单次上限 200 条。', $fH, $bH, [single]24, [single]240)
            $fH.Dispose(); $bH.Dispose()
        })

        $res = $dlg.ShowDialog()
        $titles = @(($txtList.Text -split "\r?\n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        $from = $dtpFrom.Value.Date
        $to2 = $dtpTo.Value.Date
        $allDay = $chkAll.Checked
        $hSel = $cmbHour.SelectedItem
        $mText = $cmbMin.Text.Trim()
        $dlg.Dispose()
        if ($res -ne 'OK') { return }
        if ($titles.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('请至少输入一个标题（每行一条）。', 'TrayCal', 'OK', 'Warning') | Out-Null
            return
        }
        if ($to2 -lt $from) { $tmpD = $from; $from = $to2; $to2 = $tmpD }
        $timeStr = $null
        if (-not $allDay) {
            if ($hSel -and $mText -match '^\d{1,2}$' -and [int]$mText -ge 0 -and [int]$mText -le 59) {
                $timeStr = $hSel.ToString() + ':' + ([int]$mText).ToString('00')
            } else {
                [System.Windows.Forms.MessageBox]::Show('分钟应为 0~59 的数字，例如 05。', 'TrayCal', 'OK', 'Warning') | Out-Null
                return
            }
        }
        $days = [int](($to2 - $from).TotalDays) + 1
        $count = $titles.Count * $days
        if ($count -gt 200) {
            [System.Windows.Forms.MessageBox]::Show('单次最多添加 200 条，请缩小日期范围或减少标题。', 'TrayCal', 'OK', 'Warning') | Out-Null
            return
        }
        $r = [System.Windows.Forms.MessageBox]::Show("将添加 $count 条日程（$($titles.Count) 个标题 × $days 天），确认？", 'TrayCal', 'YesNo', 'Question')
        if ($r -ne 'Yes') { return }
        $new = @(New-BatchEvents $titles $from $to2 $timeStr)
        $script:events = @($script:events) + $new
        Save-Events $DataFile $script:events
        Refresh-Panel
    } finally {
        $script:suppressHide = $false
    }
}

function Show-BatchDeleteDialog {
    $script:suppressHide = $true
    try {
        $mv = $script:viewMonth
        $rsD = $script:rangeStart; $reD = $script:rangeEnd
        if ($rsD -and $reD) {
            if ($rsD -gt $reD) { $tD = $rsD; $rsD = $reD; $reD = $tD }
            $loS = $rsD.ToString('yyyy-MM-dd')
            $hiS = $reD.ToString('yyyy-MM-dd')
            if ($loS -eq $hiS) { $subLabel = '{0}年{1}月{2}日' -f $rsD.Year, $rsD.Month, $rsD.Day }
            else { $subLabel = '{0}月{1}日~{2}月{3}日' -f $rsD.Month, $rsD.Day, $reD.Month, $reD.Day }
            $monthEvents = @($script:events | Where-Object { $_.date -ge $loS -and $_.date -le $hiS } | Sort-Object date)
        } else {
            $subLabel = '{0}年{1}月' -f $mv.Year, $mv.Month
            $monthEvents = @($script:events | Where-Object {
                try {
                    $dd = [DateTime]::ParseExact($_.date, 'yyyy-MM-dd', $null)
                    ($dd.Year -eq $mv.Year) -and ($dd.Month -eq $mv.Month)
                } catch { $false }
            } | Sort-Object date)
        }
        $dlg = New-BatchDialogBase '批量删除' 420 420
        $lvB = New-Object System.Windows.Forms.ListView
        $lvB.Location = '24,74'
        $lvB.Size = New-Object System.Drawing.Size(372, 234)
        $lvB.View = 'Details'
        $lvB.CheckBoxes = $true
        $lvB.FullRowSelect = $true
        $lvB.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)
        $lvB.Columns.Add('日期', 116) | Out-Null
        $lvB.Columns.Add('时间', 48) | Out-Null
        $lvB.Columns.Add('标题', 180) | Out-Null
        foreach ($e3 in $monthEvents) {
            $item = New-Object System.Windows.Forms.ListViewItem($e3.date)
            $item.SubItems.Add($(if ($e3.time) { $e3.time } else { '全天' })) | Out-Null
            $item.SubItems.Add($e3.title) | Out-Null
            $item.Tag = $e3.id
            $lvB.Items.Add($item) | Out-Null
        }
        $btnSel = New-TextButton '全选' $false 64 24 9
        $btnSel.Location = New-Object System.Drawing.Point(24, 322)
        $btnUnsel = New-TextButton '全不选' $false 64 24 9
        $btnUnsel.Location = New-Object System.Drawing.Point(96, 322)
        $btnDelSel = New-TextButton '删除选中' $true 100 32 10
        $btnDelSel.Location = New-Object System.Drawing.Point(192, 374)
        $btnCancel = New-TextButton '取消' $false 84 32 10
        $btnCancel.Location = New-Object System.Drawing.Point(300, 374)
        $btnSel.Add_Click({ foreach ($it in $lvB.Items) { $it.Checked = $true } })
        $btnUnsel.Add_Click({ foreach ($it in $lvB.Items) { $it.Checked = $false } })
        $btnDelSel.Add_Click({ $dlg.DialogResult = 'OK' })
        $btnCancel.Add_Click({ $dlg.DialogResult = 'Cancel' })
        $dlg.CancelButton = $btnCancel
        $dlg.Controls.AddRange(@($lvB, $btnSel, $btnUnsel, $btnDelSel, $btnCancel))
        $dlg.Add_Paint({
            param($sender, $e)
            $g = $e.Graphics
            $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
            $fL = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
            $bL = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(90, 90, 100))
            $g.DrawString(('勾选要删除的日程（' + $subLabel + '）'), $fL, $bL, [single]24, [single]52)
            $bL.Dispose(); $fL.Dispose()
            $fH = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
            $bH = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(135, 135, 145))
            $g.DrawString('勾选后点“删除选中”，删除不可撤销。', $fH, $bH, [single]24, [single]350)
            $fH.Dispose(); $bH.Dispose()
        })

        $res = $dlg.ShowDialog()
        $ids = @($lvB.CheckedItems | ForEach-Object { $_.Tag })
        $dlg.Dispose()
        if ($res -ne 'OK') { return }
        if ($ids.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('没有勾选任何日程。', 'TrayCal', 'OK', 'Information') | Out-Null
            return
        }
        $r = [System.Windows.Forms.MessageBox]::Show("删除勾选的 $($ids.Count) 条日程？", 'TrayCal', 'YesNo', 'Question')
        if ($r -ne 'Yes') { return }
        $script:events = @($script:events | Where-Object { $ids -notcontains $_.id })
        Save-Events $DataFile $script:events
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
        $r = [System.Windows.Forms.MessageBox]::Show("把 $($ws.ToString('M月d日'))~$($we.ToString('M月d日')) 的 $cnt 条日程复制到下一周？`n`n（下周由本周复制来的旧记录会被覆盖更新，手工日程不受影响）", 'TrayCal', 'YesNo', 'Question')
        if ($r -ne 'Yes') { return }
        $copies = @(Copy-WeekEvents $script:events $ws 7)
        $merged = Merge-WeekCopy $script:events $copies
        $script:events = $merged.events
        Save-Events $DataFile $script:events
        Refresh-Panel
        [System.Windows.Forms.MessageBox]::Show("已复制 $($copies.Count) 条到 $($ws.AddDays(7).ToString('M月d日'))~$($we.AddDays(7).ToString('M月d日'))：新增 $($merged.added) 条，覆盖 $($merged.replaced) 条。", 'TrayCal', 'OK', 'Information') | Out-Null
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

