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
        $src = $null
        if ($e.PSObject.Properties['sourceId'] -and $e.sourceId) { $src = [string]$e.sourceId }
        $list += @{ id = [string]$e.id; title = [string]$e.title; date = [string]$e.date;
                    time = $t; reminded = $r; snoozeUntil = $s; sourceId = $src }
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
                sourceId    = $ev.id
            }
        }
    }
    return $new
}

function Merge-WeekCopy($Events, $Copies) {
    # 同源（sourceId 相同）旧记录原地覆盖，其余追加；手工日程不受影响
    $list = @($Events)
    $added = 0
    $replaced = 0
    foreach ($cp in $Copies) {
        $idx = -1
        for ($i = 0; $i -lt $list.Count; $i++) {
            if ($list[$i].sourceId -and ($list[$i].sourceId -eq $cp.sourceId)) { $idx = $i; break }
        }
        if ($idx -ge 0) {
            $keepId = $list[$idx].id
            $list[$idx] = @{ id = $keepId; title = $cp.title; date = $cp.date; time = $cp.time;
                             reminded = $false; snoozeUntil = $null; sourceId = $cp.sourceId }
            $replaced++
        } else {
            $list = @($list) + $cp
            $added++
        }
    }
    return @{ events = $list; added = $added; replaced = $replaced }
}

function New-BatchEvents($Titles, [DateTime]$Start, [DateTime]$End, $TimeStr) {
    $evs = @()
    $d = $Start.Date
    while ($d -le $End.Date) {
        foreach ($t in $Titles) {
            $evs += @{ id = Get-NewEventId; title = $t; date = $d.ToString('yyyy-MM-dd'); time = $TimeStr;
                       reminded = $false; snoozeUntil = $null; sourceId = $null }
        }
        $d = $d.AddDays(1)
    }
    return $evs
}

