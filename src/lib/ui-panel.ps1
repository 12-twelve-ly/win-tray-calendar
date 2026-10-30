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

# ---------- 通用：窗体圆角（尺寸变化后重算，避免自动缩放错位） ----------
function Set-RoundedForm($form, [int]$r) {
    $rc = $form.ClientRectangle
    if ($rc.Width -le 0 -or $rc.Height -le 0) { return }
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddArc($rc.X, $rc.Y, $r, $r, 180, 90)
    $p.AddArc(($rc.Right - $r), $rc.Y, $r, $r, 270, 90)
    $p.AddArc(($rc.Right - $r), ($rc.Bottom - $r), $r, $r, 0, 90)
    $p.AddArc($rc.X, ($rc.Bottom - $r), $r, $r, 90, 90)
    $p.CloseFigure()
    $old = $form.Region
    $form.Region = New-Object System.Drawing.Region($p)
    $p.Dispose()
    if ($old) { $old.Dispose() }
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
$panel.Font = New-Object System.Drawing.Font('Segoe UI', 9)

# 自绘月历（原生 MonthCalendar 尺寸受系统限制，无法填满卡片）
$script:calW = 336
$script:calH = 320
$calPanel = New-Object System.Windows.Forms.Panel
$calPanel.Size = New-Object System.Drawing.Size($script:calW, $script:calH)
try {
    $calPanel.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic').SetValue($calPanel, $true)
} catch { }
$panel.Controls.Add($calPanel) | Out-Null

# 日期标题不再用 Label，而是在面板 Paint 中用 GDI+ 直绘（与日历数字同渲染路径，不发虚）
$script:selText = ''

$lv = New-Object System.Windows.Forms.ListView
$lv.View = 'Details'
$lv.FullRowSelect = $true
$lv.MultiSelect = $false
$lv.HideSelection = $false
$lv.HeaderStyle = 'None'
$lv.BorderStyle = 'None'
$lv.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)
$rowImg = New-Object System.Windows.Forms.ImageList
$rowImg.ImageSize = New-Object System.Drawing.Size(1, 26)
$tmpRowBmp = New-Object System.Drawing.Bitmap(1, 26)
$rowImg.Images.Add($tmpRowBmp) | Out-Null
$lv.SmallImageList = $rowImg
$lv.Columns.Add('时间', 58) | Out-Null
$lv.Columns.Add('日程', 292) | Out-Null
$panel.Controls.Add($lv) | Out-Null

function New-TextButton($caption, [bool]$accent, [int]$w = 84, [int]$h = 30, [int]$size = 10) {
    # 自绘按钮：文字用 GDI+ ClearType 渲染，避免原生按钮文字发虚
    $b = New-Object System.Windows.Forms.Button
    $b.Text = ''
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.BackColor = $(if ($accent) { [System.Drawing.Color]::FromArgb(0, 120, 215) } else { [System.Drawing.Color]::White })
    $b.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', $size)
    $b | Add-Member -NotePropertyName Caption -NotePropertyValue $caption -Force
    $b | Add-Member -NotePropertyName Accent -NotePropertyValue $accent -Force
    $b.Add_MouseEnter({
        param($s, $e)
        if (-not $s.Enabled) { return }
        $s.BackColor = $(if ($s.Accent) { [System.Drawing.Color]::FromArgb(0, 104, 188) } else { [System.Drawing.Color]::FromArgb(240, 243, 247) })
    })
    $b.Add_MouseLeave({
        param($s, $e)
        $s.BackColor = $(if ($s.Accent) { [System.Drawing.Color]::FromArgb(0, 120, 215) } else { [System.Drawing.Color]::White })
    })
    $b.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
        $rc = $sender.ClientRectangle
        $isLink = ($sender.PSObject.Properties['Style'] -and $sender.Style -eq 'link')
        if (-not $sender.Enabled) { $fgc = [System.Drawing.Color]::FromArgb(170, 170, 176) }
        elseif ($isLink) { $fgc = [System.Drawing.Color]::FromArgb(0, 110, 200) }
        elseif ($sender.Accent) { $fgc = [System.Drawing.Color]::White }
        else { $fgc = [System.Drawing.Color]::FromArgb(45, 45, 55) }
        if (-not $sender.Accent -and -not $isLink) {
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210, 210, 218), 1)
            $g.DrawRectangle($pen, $rc.X, $rc.Y, ($rc.Width - 1), ($rc.Height - 1))
            $pen.Dispose()
        }
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = [System.Drawing.StringAlignment]::Center
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        $br = New-Object System.Drawing.SolidBrush($fgc)
        $g.DrawString($sender.Caption, $sender.Font, $br, (New-Object System.Drawing.RectangleF(0, 0, $rc.Width, $rc.Height)), $sf)
        $br.Dispose(); $sf.Dispose()
    })
    return $b
}

function New-PanelButton($text, $accent) {
    return New-TextButton $text ([bool]$accent) 72 30 10
}
$btnAdd = New-PanelButton '添加日程' $true
$btnEdit = New-PanelButton '编辑' $false
$btnDel = New-PanelButton '删除' $false
$btnCopyWeek = New-PanelButton '复制本周→下周' $false
$btnCopyWeek.Size = New-Object System.Drawing.Size(128, 24)
$btnCopyWeek.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$btnCopyWeek | Add-Member -NotePropertyName Style -NotePropertyValue 'link' -Force
$btnMove = New-PanelButton '移动' $false
$btnMove.Add_Click({
    if ($script:moveMode) {
        $script:moveMode = $false
        $script:moveEvId = $null
        $btnMove.Caption = '移动'
        $btnMove.Invalidate()
        Refresh-Panel
        return
    }
    $selEv = Get-SelectedEvent
    if (-not $selEv) {
        [System.Windows.Forms.MessageBox]::Show('先在列表里选中一条日程。', 'TrayCal', 'OK', 'Information') | Out-Null
        return
    }
    $script:moveMode = $true
    $script:moveEvId = $selEv.id
    $btnMove.Caption = '取消'
    $btnMove.Invalidate()
    Refresh-Panel
})
$panel.Controls.AddRange(@($btnAdd, $btnMove, $btnEdit, $btnDel, $btnCopyWeek))

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
    $w = $script:calW
    $h = $script:calH
    $lvH = 120
    $btnH = 32
    $rowH = 38          # 日期行（上间距加大）
    $gap  = 12          # 列表与按钮行的间距
    $panel.ClientSize = New-Object System.Drawing.Size(($w + $pad * 2), ($pad + $h + $rowH + $lvH + $gap + $btnH + $pad))
    $calPanel.Location = New-Object System.Drawing.Point($pad, $pad)
    $btnCopyWeek.Location = New-Object System.Drawing.Point(($pad + $w - 128), ($pad + $h + 10))
    $lv.Location = New-Object System.Drawing.Point($pad, ($pad + $h + $rowH + 2))
    $lv.Size = New-Object System.Drawing.Size($w, $lvH)
    # 列宽自适应，不产生横向滚动条
    $lv.Columns[0].Width = 58
    $lv.Columns[1].Width = [Math]::Max(120, ($w - 58 - 24))
    $by = ($pad + $h + $rowH + 2 + $lvH + $gap)
    $btnAdd.Size = New-Object System.Drawing.Size(86, $btnH)
    $btnAdd.Location = New-Object System.Drawing.Point($pad, $by)
    $btnMove.Size = New-Object System.Drawing.Size(72, $btnH)
    $btnMove.Location = New-Object System.Drawing.Point(($pad + 86 + 10), $by)
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
    # 日期标题（GDI+ ClearType 直绘，与日历数字一致）
    if ($script:selText) {
        $e.Graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
        $tf = New-Object System.Drawing.Font('Microsoft YaHei UI', 11)
        $tb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(25, 25, 25))
        $e.Graphics.DrawString($script:selText, $tf, $tb, [single]($pad + 2), [single]($pad + $script:calH + 10))
        $tf.Dispose(); $tb.Dispose()
    }
})

# ---------- 面板行为 ----------
function Refresh-Panel {
    $sel = $script:selectedDate
    if ($script:moveMode) {
        $script:selText = '移动中：点日历日期'
    } elseif ($script:rangeStart -and $script:rangeEnd -and ($script:rangeStart -ne $script:rangeEnd)) {
        $lo = $script:rangeStart; $hi = $script:rangeEnd
        if ($lo -gt $hi) { $t3 = $lo; $lo = $hi; $hi = $t3 }
        $script:selText = '{0}月{1}日~{2}月{3}日 日程' -f $lo.Month, $lo.Day, $hi.Month, $hi.Day
    } else {
        $lunSel = Get-LunarInfo $sel
        $lunSuffix = $(if ($lunSel.Text) { ' ' + $lunSel.Text } else { '' })
        $script:selText = '{0}年{1}月{2}日{3}' -f $sel.Year, $sel.Month, $sel.Day, $lunSuffix
    }
    $script:eventDates = @{}
    foreach ($e2 in $script:events) { $script:eventDates[$e2.date] = $true }
    $calPanel.Invalidate()
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
    $btnMove.Enabled = (($lv.SelectedItems.Count -gt 0) -or $script:moveMode)
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
function Hide-Panel {
    $script:moveMode = $false
    $script:moveEvId = $null
    if ($btnMove) { $btnMove.Caption = '移动'; $btnMove.Invalidate() }
    $panel.Hide()
}
function Toggle-Panel { if ($panel.Visible) { Hide-Panel } else { Show-Panel } }

$panel.Add_Deactivate({
    if (-not $script:suppressHide -and -not $KeepOpen -and $panel.Visible) { Hide-Panel }
})

$calPanel.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $W = $sender.Width; $H = $sender.Height
    $headH = 34.0
    $vm = $script:viewMonth
    $mode = $script:calMode
    $today = (Get-Date).Date
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $fontTitle = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $fontDay   = New-Object System.Drawing.Font('Segoe UI', 11)
    $fontWd    = New-Object System.Drawing.Font('Segoe UI', 9)
    $gray  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(165, 165, 175))
    $dark  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(45, 45, 55))
    $blue  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 120, 215))
    $white = [System.Drawing.Brushes]::White
    $pen   = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0, 120, 215), 1.6)

    if ($mode -eq 'month') { $title = '{0}年' -f $vm.Year }
    elseif ($mode -eq 'year') { $ys0 = $vm.Year - ($vm.Year % 12); $title = '{0} - {1}' -f $ys0, ($ys0 + 11) }
    else { $title = '{0}年{1}月' -f $vm.Year, $vm.Month }
    $g.DrawString($title, $fontTitle, $dark, (New-Object System.Drawing.RectangleF(0, 0, $W, $headH)), $sf)
    $g.DrawString([string][char]0x2039, $fontTitle, $gray, (New-Object System.Drawing.RectangleF(2, 0, 32, $headH)), $sf)
    $g.DrawString([string][char]0x203A, $fontTitle, $gray, (New-Object System.Drawing.RectangleF(($W - 34), 0, 32, $headH)), $sf)

    if ($mode -eq 'day') {
        $wdH = 24.0
        $cellW = $W / 7.0
        $cellH = ($H - $headH - $wdH) / 6.0
        $names = @('一', '二', '三', '四', '五', '六', '日')
        for ($i = 0; $i -lt 7; $i++) {
            $r = New-Object System.Drawing.RectangleF(($i * $cellW), $headH, $cellW, $wdH)
            $g.DrawString($names[$i], $fontWd, $gray, $r, $sf)
        }
        $dowOff = (([int]$vm.DayOfWeek) + 6) % 7
        $start = $vm.AddDays(-$dowOff)
        $fontLun = New-Object System.Drawing.Font('Microsoft YaHei UI', 7.5)
        $lumGray = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(152, 152, 164))
        $lumTerm = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 120, 215))
        for ($row = 0; $row -lt 6; $row++) {
            for ($col = 0; $col -lt 7; $col++) {
                $d = $start.AddDays($row * 7 + $col)
                $rect = New-Object System.Drawing.RectangleF(($col * $cellW), ($headH + $wdH + $row * $cellH), $cellW, $cellH)
                $cx = $rect.X + $cellW / 2.0
                $numRect = New-Object System.Drawing.RectangleF($rect.X, ($rect.Y + 1), $cellW, 26)
                $cy = $rect.Y + 14.0
                if ($script:rangeStart -and $script:rangeEnd) {
                    $lo = $script:rangeStart; $hi = $script:rangeEnd
                    if ($lo -gt $hi) { $t2 = $lo; $lo = $hi; $hi = $t2 }
                    if (($d -ge $lo) -and ($d -le $hi) -and ($d -ne $today)) {
                        $band = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(224, 237, 250))
                        $g.FillRectangle($band, [single]($rect.X + 4), [single]($rect.Y + 2), [single]($cellW - 8), [single]($cellH - 6))
                        $band.Dispose()
                    }
                }
                if ($d -eq $today) {
                    $g.FillEllipse($blue, [single]($cx - 15), [single]($cy - 15), 30, 30)
                    $g.DrawString([string]$d.Day, $fontDay, $white, $numRect, $sf)
                } else {
                    if ($d -eq $script:selectedDate) {
                        $g.DrawEllipse($pen, [single]($cx - 15), [single]($cy - 15), 30, 30)
                    }
                    $brush = if ($d.Month -ne $vm.Month) { $gray } else { $dark }
                    $g.DrawString([string]$d.Day, $fontDay, $brush, $numRect, $sf)
                }
                $lun = Get-LunarInfo $d
                if ($lun.Text) {
                    $lr = New-Object System.Drawing.RectangleF($rect.X, ($rect.Y + 26), $cellW, 13)
                    $lb = $(if ($lun.IsTerm -and ($d.Month -eq $vm.Month)) { $lumTerm } else { $lumGray })
                    $g.DrawString($lun.Text, $fontLun, $lb, $lr, $sf)
                }
                if ($script:eventDates.ContainsKey($d.ToString('yyyy-MM-dd'))) {
                    $g.FillEllipse($blue, [single]($cx - 2.5), [single]($rect.Y + $cellH - 7), 5, 5)
                }
            }
        }
        $fontLun.Dispose(); $lumGray.Dispose(); $lumTerm.Dispose()
    } else {
        # 月/年选择：3 列 × 4 行
        $cw = $W / 3.0
        $ch = ($H - $headH) / 4.0
        $yrStart = $vm.Year - ($vm.Year % 12)
        for ($i = 0; $i -lt 12; $i++) {
            $row = [int][Math]::Floor($i / 3); $col = $i % 3
            $rect = New-Object System.Drawing.RectangleF(($col * $cw), ($headH + $row * $ch), $cw, $ch)
            $cx = $rect.X + $cw / 2.0; $cy = $rect.Y + $ch / 2.0
            if ($mode -eq 'month') {
                $txt = '{0}月' -f ($i + 1)
                $isToday = ($vm.Year -eq $today.Year -and ($i + 1) -eq $today.Month)
                $isSel = (($i + 1) -eq $vm.Month)
            } else {
                $txt = [string]($yrStart + $i)
                $isToday = (($yrStart + $i) -eq $today.Year)
                $isSel = (($yrStart + $i) -eq $vm.Year)
            }
            if ($isToday) {
                $g.FillEllipse($blue, [single]($cx - 26), [single]($cy - 20), 52, 40)
                $g.DrawString($txt, $fontDay, $white, $rect, $sf)
            } else {
                if ($isSel) { $g.DrawEllipse($pen, [single]($cx - 26), [single]($cy - 20), 52, 40) }
                $g.DrawString($txt, $fontDay, $dark, $rect, $sf)
            }
        }
    }
    $pen.Dispose()
    $fontTitle.Dispose(); $fontDay.Dispose(); $fontWd.Dispose()
    $gray.Dispose(); $dark.Dispose(); $blue.Dispose()
})

function Get-DateAtPoint($sender, [int]$x, [int]$y) {
    $headH = 34.0; $wdH = 24.0
    if ($script:calMode -ne 'day') { return $null }
    if ($y -lt ($headH + $wdH)) { return $null }
    $cellW = $sender.Width / 7.0
    $cellH = ($sender.Height - $headH - $wdH) / 6.0
    $c = [int][Math]::Floor($x / $cellW)
    $r = [int][Math]::Floor(($y - $headH - $wdH) / $cellH)
    if ($c -lt 0 -or $c -gt 6 -or $r -lt 0 -or $r -gt 5) { return $null }
    $dowOff = (([int]$script:viewMonth.DayOfWeek) + 6) % 7
    return $script:viewMonth.AddDays(-$dowOff + $r * 7 + $c).Date
}

$calPanel.Add_MouseDown({
    param($sender, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $d = Get-DateAtPoint $sender $e.X $e.Y
    if (-not $d) { return }
    $script:rangeStart = $d
    $script:rangeEnd = $d
    $sender.Invalidate()
})

$calPanel.Add_MouseMove({
    param($sender, $e)
    if (-not $script:rangeStart) { return }
    if ([System.Windows.Forms.Control]::MouseButtons -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $d = Get-DateAtPoint $sender $e.X $e.Y
    if (-not $d) { return }
    if ($d -ne $script:rangeEnd) {
        $script:rangeEnd = $d
        $sender.Invalidate()
    }
})

$calPanel.Add_MouseUp({
    param($sender, $e)
    if ($script:moveMode) {
        $mvD = Get-DateAtPoint $sender $e.X $e.Y
        if ($mvD) {
            $mvId = $script:moveEvId
            $script:moveMode = $false
            $script:moveEvId = $null
            $btnMove.Caption = '移动'
            $btnMove.Invalidate()
            Invoke-MoveEventToDate $mvId $mvD
            return
        }
    }
    $W = $sender.Width; $H = $sender.Height
    $headH = 34.0
    $mode = $script:calMode
    if ($e.Y -lt $headH) {
        if ($e.X -lt 40) {
            if ($mode -eq 'month') { $script:viewMonth = $script:viewMonth.AddYears(-1) }
            elseif ($mode -eq 'year') { $script:viewMonth = $script:viewMonth.AddYears(-12) }
            else { $script:viewMonth = $script:viewMonth.AddMonths(-1) }
        } elseif ($e.X -gt ($W - 40)) {
            if ($mode -eq 'month') { $script:viewMonth = $script:viewMonth.AddYears(1) }
            elseif ($mode -eq 'year') { $script:viewMonth = $script:viewMonth.AddYears(12) }
            else { $script:viewMonth = $script:viewMonth.AddMonths(1) }
        } else {
            if ($mode -eq 'day') { $script:calMode = 'month' }
            elseif ($mode -eq 'month') { $script:calMode = 'year' }
            else { $script:calMode = 'day' }
        }
        $sender.Invalidate()
        return
    }
    if ($mode -eq 'day') {
        $d = Get-DateAtPoint $sender $e.X $e.Y
        if (-not $d) { return }
        $isPlainClick = ($script:rangeStart -eq $script:rangeEnd)
        if ($null -eq $script:rangeStart) { $script:rangeStart = $d; $script:rangeEnd = $d }
        else { $script:rangeEnd = $d }
        if ($isPlainClick -and ($d.Month -ne $script:viewMonth.Month)) {
            $script:viewMonth = New-Object DateTime($d.Year, $d.Month, 1)
        }
        $script:selectedDate = $d
        Refresh-Panel
        return
    }
    $cw = $W / 3.0
    $ch = ($H - $headH) / 4.0
    $col = [int][Math]::Floor($e.X / $cw)
    $row = [int][Math]::Floor(($e.Y - $headH) / $ch)
    if ($col -lt 0 -or $col -gt 2 -or $row -lt 0 -or $row -gt 3) { return }
    $idx = $row * 3 + $col
    if ($mode -eq 'month') {
        $script:viewMonth = New-Object DateTime($script:viewMonth.Year, ($idx + 1), 1)
        $script:calMode = 'day'
    } else {
        $ys1 = $script:viewMonth.Year - ($script:viewMonth.Year % 12)
        $script:viewMonth = New-Object DateTime(($ys1 + $idx), $script:viewMonth.Month, 1)
        $script:calMode = 'month'
    }
    $sender.Invalidate()
})

# 改期核心：移动模式（先在列表选中日程，再点日历日期）
function Invoke-MoveEventToDate([string]$evId, [DateTime]$target) {
    $evTarget = $script:events | Where-Object { $_.id -eq $evId } | Select-Object -First 1
    if (-not $evTarget) { return }
    if ($evTarget.date -eq $target.ToString('yyyy-MM-dd')) { return }
    $script:events = @(Move-EventToDate $script:events $evTarget.id $target)
    Save-Events $DataFile $script:events
    if ($target.Month -ne $script:viewMonth.Month -or $target.Year -ne $script:viewMonth.Year) {
        $script:viewMonth = New-Object DateTime($target.Year, $target.Month, 1)
    }
    $script:selectedDate = $target
    $script:rangeStart = $target
    $script:rangeEnd = $target
    Refresh-Panel
}

# 滚轮切换月份：悬停日历区时把焦点交给面板，滚轮在面板上被处理
# 注意：移动模式下不抢焦点，避免打断操作
$calPanel.Add_MouseEnter({ if (-not $script:moveMode) { $panel.Focus() } })
$panel.Add_MouseWheel({
    param($sender, $e)
    $pt = $panel.PointToClient([System.Windows.Forms.Cursor]::Position)
    if (-not $calPanel.Bounds.Contains($pt)) { return }
    if ($script:calMode -eq 'day') {
        if ($e.Delta -gt 0) { $script:viewMonth = $script:viewMonth.AddMonths(-1) } else { $script:viewMonth = $script:viewMonth.AddMonths(1) }
    } elseif ($script:calMode -eq 'month') {
        if ($e.Delta -gt 0) { $script:viewMonth = $script:viewMonth.AddYears(-1) } else { $script:viewMonth = $script:viewMonth.AddYears(1) }
    } else {
        if ($e.Delta -gt 0) { $script:viewMonth = $script:viewMonth.AddYears(-12) } else { $script:viewMonth = $script:viewMonth.AddYears(12) }
    }
    $calPanel.Invalidate()
})

$lv.Add_SelectedIndexChanged({
    $btnEdit.Enabled = ($lv.SelectedItems.Count -gt 0)
    $btnDel.Enabled = ($lv.SelectedItems.Count -gt 0)
    $btnMove.Enabled = (($lv.SelectedItems.Count -gt 0) -or $script:moveMode)
})


