# 农历与二十四节气
# 农历：.NET 内置 ChineseLunisolarCalendar（零依赖）
# 节气：通用公式（2000-2099 世纪常数），2025/2026/2027 已与权威数据核对；
#      已知特例在 Get-SolarTermsForYear 中修正（目前收录 2026 年雨水）

$script:lunarCal = New-Object System.Globalization.ChineseLunisolarCalendar
$script:termCache = @{}

function Get-LunarDayName([int]$day) {
    $nums = @('一', '二', '三', '四', '五', '六', '七', '八', '九', '十')
    if ($day -le 10) { return '初' + $nums[$day - 1] }
    if ($day -lt 20) { return '十' + $nums[$day - 11] }
    if ($day -eq 20) { return '二十' }
    if ($day -lt 30) { return '廿' + $nums[$day - 21] }
    return '三十'
}

function Get-SolarTermsForYear([int]$y) {
    $names = @('小寒', '大寒', '立春', '雨水', '惊蛰', '春分', '清明', '谷雨', '立夏', '小满', '芒种', '夏至',
               '小暑', '大暑', '立秋', '处暑', '白露', '秋分', '寒露', '霜降', '立冬', '小雪', '大雪', '冬至')
    $months = @(1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12)
    $constants = @(5.4055, 20.12, 3.87, 18.73, 5.63, 20.646, 4.81, 20.1, 5.52, 21.04, 5.678, 21.37,
                   7.108, 22.83, 7.5, 23.13, 7.646, 23.042, 8.318, 23.438, 7.438, 22.36, 7.18, 21.94)
    $y2 = $y % 100
    $leapAdj = [int][Math]::Floor(($y2 - 1) / 4)
    $map = @{}
    for ($i = 0; $i -lt 24; $i++) {
        $day = [int][Math]::Floor($y2 * 0.2422 + $constants[$i]) - $leapAdj
        # 已知特例修正（与紫金山天文台/香港天文台数据核对）
        if ($y -eq 2026 -and $names[$i] -eq '雨水') { $day = $day - 1 }
        $map[('{0:00}-{1:00}' -f $months[$i], $day)] = $names[$i]
    }
    return $map
}

function Get-SolarTermName([DateTime]$d) {
    $y = $d.Year
    if ($y -lt 2000 -or $y -gt 2099) { return $null }
    if (-not $script:termCache.ContainsKey($y)) {
        $script:termCache[$y] = Get-SolarTermsForYear $y
    }
    $key = $d.ToString('MM-dd')
    $t = $script:termCache[$y]
    if ($t.ContainsKey($key)) { return $t[$key] }
    return $null
}

function Get-LunarInfo([DateTime]$d) {
    # 返回 @{ Text = 格子下方小字; IsTerm = 是否节气 }
    $d = $d.Date
    $term = Get-SolarTermName $d
    if ($term) { return @{ Text = $term; IsTerm = $true } }
    try {
        $cal = $script:lunarCal
        $ld = $cal.GetDayOfMonth($d)
        $lm = $cal.GetMonth($d)
        $ly = $cal.GetYear($d)
        $leap = $cal.GetLeapMonth($ly)
        $isLeap = $false
        if ($leap -gt 0) {
            if ($lm -eq $leap) { $isLeap = $true }
            elseif ($lm -gt $leap) { $lm = $lm - 1 }
        }
        if ($ld -eq 1) {
            $names = @('正月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '冬月', '腊月')
            $txt = $(if ($isLeap) { '闰' } else { '' }) + $names[$lm - 1]
        } else {
            $txt = Get-LunarDayName $ld
        }
        return @{ Text = $txt; IsTerm = $false }
    } catch {
        return @{ Text = ''; IsTerm = $false }
    }
}
