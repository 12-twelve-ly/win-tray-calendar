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
        Assert ($copied[0].sourceId -eq 'x1') '复制周：记录来源 id'
        $targets = @(
            @{ id = 'y1'; title = '旧标题'; date = '2026-11-03'; time = '10:00'; reminded = $true; snoozeUntil = $null; sourceId = 'x1' },
            @{ id = 'y2'; title = '手工事项'; date = '2026-11-04'; time = $null; reminded = $false; snoozeUntil = $null; sourceId = $null }
        )
        $m = Merge-WeekCopy $targets $copied
        Assert ($m.replaced -eq 1) '覆盖：同源旧记录被覆盖'
        Assert ($m.added -eq 0) '覆盖：无新增'
        Assert ($m.events.Count -eq 2) '覆盖：总条数不变'
        Assert ((@($m.events | Where-Object { $_.id -eq 'y1' })[0]).title -eq '本周事项') '覆盖：内容更新为来源标题'
        Assert ((@($m.events | Where-Object { $_.id -eq 'y1' })[0]).reminded -eq $false) '覆盖：提醒状态重置'
        Assert ((@($m.events | Where-Object { $_.id -eq 'y2' })[0]).title -eq '手工事项') '覆盖：手工日程不受影响'
        $bt = @('打卡', '写周报')
        $be = @(New-BatchEvents $bt ([DateTime]'2026-11-02') ([DateTime]'2026-11-04') '09:00')
        Assert ($be.Count -eq 6) '批量添加：标题数×天数'
        Assert ((@($be | Where-Object { $_.date -eq '2026-11-03' })).Count -eq 2) '批量添加：中间日期各标题一条'
        Assert ($be[0].time -eq '09:00') '批量添加：时间写入'
        $be2 = @(New-BatchEvents @('全天事项') ([DateTime]'2026-11-02') ([DateTime]'2026-11-02') $null)
        Assert (($be2.Count -eq 1) -and ($null -eq $be2[0].time)) '批量添加：全天单日'
        $mvSrc = @(@{ id = 'm1'; title = '改期测试'; date = '2026-10-29'; time = '10:00'; reminded = $false; snoozeUntil = $null; sourceId = $null })
        $mvPast = @(Move-EventToDate $mvSrc 'm1' ([DateTime]'2020-01-01'))
        Assert ($mvPast[0].date -eq '2020-01-01') '改期：日期更新'
        Assert ($mvPast[0].reminded -eq $true) '改期：移到过去日期标记已提醒'
        $mvFut = @(Move-EventToDate $mvSrc 'm1' ([DateTime]'2099-01-01'))
        Assert ($mvFut[0].reminded -eq $false) '改期：移到未来日期重置提醒'
        Assert ($mvFut[0].time -eq '10:00') '改期：时间保持不变'
        $li1 = Get-LunarInfo ([DateTime]'2026-02-17')
        Assert ($li1.Text -eq '正月') '农历：2026-02-17 为正月初一（春节）'
        $li2 = Get-LunarInfo ([DateTime]'2026-12-22')
        Assert ($li2.IsTerm -and ($li2.Text -eq '冬至')) '节气：2026-12-22 冬至'
        $li3 = Get-LunarInfo ([DateTime]'2026-02-18')
        Assert ($li3.IsTerm -and ($li3.Text -eq '雨水')) '节气：2026-02-18 雨水（特例修正）'
        $t26 = Get-SolarTermsForYear 2026
        Assert (@($t26.Keys).Count -eq 24) '节气：2026 全年 24 个'
        Assert ($t26['02-04'] -eq '立春') '节气：2026-02-04 立春'
        $t25 = Get-SolarTermsForYear 2025
        Assert ($t25['03-20'] -eq '春分') '节气：2025-03-20 春分（核对）'
        $t27 = Get-SolarTermsForYear 2027
        Assert ($t27['02-19'] -eq '雨水') '节气：2027-02-19 雨水（核对）'
    } finally { Remove-Item $tmpFile -ErrorAction SilentlyContinue }
    if ($fail -eq 0) { Write-Host 'SelfTest 全部通过' -ForegroundColor Green; $script:testExitCode = 0 }
    else { Write-Host "SelfTest 失败 $fail 项" -ForegroundColor Red; $script:testExitCode = 1 }
}

