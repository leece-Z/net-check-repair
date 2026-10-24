# ============================================================
#  网络检查与修复工具  net_check.ps1
#  功能：全面检查 8 项网络配置 + 一键修复（自动备份、可回滚）
#  依赖：Windows 10/11，管理员权限（由同目录 .bat 自提权启动）
# ============================================================
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# ---------- 程序集 ----------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Data

# ---------- 自提权（直接运行本脚本时） ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath) -Verb RunAs -WindowStyle Hidden
    exit
}

# ---------- 全局 ----------
$script:BackupRoot = Join-Path $PSScriptRoot 'backup'
$HostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$script:checks = $null

# ---------- 物理网卡判定（排除 VirtualBox/VMware 等虚拟网卡） ----------
function Get-PhysicalAdapter {
    $exclude = 'virtualbox|vmware|hyper-v|loopback|tap|virtual|tunnel|isatap|teredo|6to4|vpn'
    return @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -notmatch $exclude })
}

function Get-PhysicalConnectedCount {
    return @(Get-PhysicalAdapter | Where-Object { $_.MediaConnectionState -eq 'Connected' }).Count
}

# ============================================================
#  检查函数：均返回 @{ Name; Status; Detail }
#  状态取值：正常 / 异常 / 受断网影响
# ============================================================
function Check-Hardware {
    $a = @(Get-PhysicalAdapter)
    if ($a.Count -eq 0) { return @{ Name = '网络硬件配置'; Status = '异常'; Detail = '未检测到物理网卡' } }
    $dis = @($a | Where-Object { $_.Status -eq 'Disabled' })
    if ($dis.Count -gt 0) {
        return @{ Name = '网络硬件配置'; Status = '异常'; Detail = ('有网卡被禁用: ' + ($dis.Name -join ', ')) }
    }
    $conn = @($a | Where-Object { $_.MediaConnectionState -eq 'Connected' })
    if ($conn.Count -eq 0) {
        return @{ Name = '网络硬件配置'; Status = '异常'; Detail = ('物理网卡未连接（请检查网线）: ' + ($a.Name -join ', ')) }
    }
    return @{ Name = '网络硬件配置'; Status = '正常'; Detail = ('已连接网卡: ' + ($conn.Name -join ', ')) }
}

function Check-NetConfig {
    $idx = @(Get-PhysicalAdapter | Select-Object -ExpandProperty InterfaceIndex)
    if ($idx.Count -eq 0) { return @{ Name = '网络连接配置'; Status = '异常'; Detail = '未检测到物理网卡' } }
    if ((Get-PhysicalConnectedCount) -eq 0) {
        return @{ Name = '网络连接配置'; Status = '受断网影响'; Detail = '物理网卡未连接，跳过 IP/网关判定' }
    }
    $ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $idx -contains $_.InterfaceIndex -and $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' })
    if ($ips.Count -eq 0) { return @{ Name = '网络连接配置'; Status = '异常'; Detail = '物理网卡未获取到有效 IPv4 地址' } }
    $gw = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Where-Object { $idx -contains $_.InterfaceIndex })
    if ($gw.Count -eq 0) { return @{ Name = '网络连接配置'; Status = '异常'; Detail = '物理网卡已获取 IP 但无默认网关（可能 DHCP 异常）' } }
    return @{ Name = '网络连接配置'; Status = '正常'; Detail = ('IP: ' + (($ips | ForEach-Object { $_.IPAddress }) -join ', ')) }
}

function Check-Dhcp {
    $s = Get-Service Dhcp -ErrorAction SilentlyContinue
    if (-not $s) { return @{ Name = 'DHCP 服务'; Status = '异常'; Detail = 'DHCP 服务不存在' } }
    if ($s.Status -ne 'Running') { return @{ Name = 'DHCP 服务'; Status = '异常'; Detail = ('DHCP 服务状态: ' + $s.Status) } }
    if ($s.StartType -ne 'Automatic') { return @{ Name = 'DHCP 服务'; Status = '异常'; Detail = ('DHCP 启动类型为 ' + $s.StartType + '（应为 Automatic）') } }
    return @{ Name = 'DHCP 服务'; Status = '正常'; Detail = '运行中，启动类型 Automatic' }
}

function Check-Dns {
    $s = Get-Service Dnscache -ErrorAction SilentlyContinue
    if (-not $s -or $s.Status -ne 'Running') {
        return @{ Name = 'DNS 服务'; Status = '异常'; Detail = 'DNS 客户端服务未运行' }
    }
    if ((Get-PhysicalConnectedCount) -eq 0) {
        return @{ Name = 'DNS 服务'; Status = '受断网影响'; Detail = 'DNS 服务运行中；物理断网，跳过解析判定' }
    }
    try {
        $r = Resolve-DnsName -Name 'www.baidu.com' -Type A -DnsOnly -ErrorAction Stop | Select-Object -First 1
        if ($r) { return @{ Name = 'DNS 服务'; Status = '正常'; Detail = ('运行中；解析测试通过: ' + $r.IPAddress) } }
        return @{ Name = 'DNS 服务'; Status = '异常'; Detail = '运行中；解析测试无结果' }
    } catch {
        return @{ Name = 'DNS 服务'; Status = '异常'; Detail = ('运行中；DNS 解析失败: ' + $_.Exception.Message) }
    }
}

function Check-Hosts {
    $lines = @(Get-Content -LiteralPath $HostsPath -ErrorAction SilentlyContinue)
    if ($lines.Count -eq 0) { return @{ Name = 'HOSTS 文件'; Status = '正常'; Detail = 'HOSTS 文件为空' } }
    $active = @($lines | Where-Object { $_ -match '^\s*[^#\s]' })
    $suspicious = @()
    foreach ($line in $active) {
        $t = $line.Trim()
        if ($t -like '127.0.0.1*localhost*' -or $t -like '::1*localhost*') { continue }
        $suspicious += $t
    }
    if ($suspicious.Count -gt 0) {
        return @{ Name = 'HOSTS 文件'; Status = '异常'; Detail = ('存在可疑映射: ' + ($suspicious -join ' | ')) }
    }
    return @{ Name = 'HOSTS 文件'; Status = '正常'; Detail = '未发现可疑映射' }
}

function Check-Lsp {
    $out = netsh winsock show catalog 2>&1 | Out-String
    $dlls = [regex]::Matches($out, '([A-Za-z]:\\[^\r\n]*?\.(?:dll|sys))') | ForEach-Object { $_.Groups[1].Value }
    $nonSys = @($dlls | Where-Object { $_ -and $_ -notmatch '^[Cc]:\\Windows\\' })
    if ($nonSys.Count -gt 0) {
        return @{ Name = 'LSP 协议'; Status = '异常'; Detail = ('发现非系统 LSP: ' + ($nonSys -join ', ')) }
    }
    return @{ Name = 'LSP 协议'; Status = '正常'; Detail = '未发现异常 LSP 条目' }
}

function Check-Proxy {
    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $enable = (Get-ItemProperty -Path $k -Name ProxyEnable -ErrorAction SilentlyContinue).ProxyEnable
    $server = (Get-ItemProperty -Path $k -Name ProxyServer -ErrorAction SilentlyContinue).ProxyServer
    $auto = (Get-ItemProperty -Path $k -Name AutoConfigURL -ErrorAction SilentlyContinue).AutoConfigURL
    $hasProxy = ($enable -eq 1) -or [bool]$server -or [bool]$auto

    if ((Get-PhysicalConnectedCount) -eq 0) {
        return @{ Name = 'IE 代理'; Status = '受断网影响'; Detail = '物理断网，跳过代理连通判定' }
    }

    # 测试地址：无代理 = 百度；有代理 = 百度 + 谷歌（补充）
    $urls = @('http://www.baidu.com')
    if ($hasProxy) { $urls += 'https://www.google.com' }

    $okList = @()
    $failList = @()
    foreach ($u in $urls) {
        $ok = $false
        try {
            $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 6 -ErrorAction Stop
            if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 400) { $ok = $true }
        } catch {
            $ok = $false
        }
        if ($ok) { $okList += $u } else { $failList += $u }
    }

    if (-not $hasProxy) {
        if ($okList.Count -gt 0) {
            return @{ Name = 'IE 代理'; Status = '正常'; Detail = ('未启用代理；网络通畅（' + ($okList -join ', ') + '）') }
        }
        return @{ Name = 'IE 代理'; Status = '异常'; Detail = ('未启用代理；网络不通（' + ($failList -join ', ') + '）') }
    }

    $d = @()
    if ($enable -eq 1) { $d += '代理已开启' }
    if ($server) { $d += ('代理地址: ' + $server) }
    if ($auto) { $d += ('自动配置: ' + $auto) }
    $head = ($d -join '；')
    if ($failList.Count -eq 0) {
        return @{ Name = 'IE 代理'; Status = '正常'; Detail = ($head + '；代理后网络通畅（' + ($okList -join ', ') + '）') }
    }
    return @{ Name = 'IE 代理'; Status = '异常'; Detail = ($head + '；存在异常地址: ' + ($failList -join ', ')) }
}

function Check-Env {
    $probs = @()
    if (-not $env:SystemRoot) { $probs += 'SystemRoot 缺失' }
    if (-not $env:TEMP) { $probs += 'TEMP 缺失' }
    $path = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if (-not $path) { $probs += '系统 PATH 为空' }
    elseif ($path.Contains(';;')) { $probs += 'PATH 存在空项(;;)' }
    if ($probs.Count -gt 0) { return @{ Name = '环境变量'; Status = '异常'; Detail = ($probs -join '；') } }
    return @{ Name = '环境变量'; Status = '正常'; Detail = '关键环境变量正常' }
}

function Get-CheckList {
    $out = @()
    $out += (Check-Hardware)
    $out += (Check-NetConfig)
    $out += (Check-Dhcp)
    $out += (Check-Dns)
    $out += (Check-Hosts)
    $out += (Check-Lsp)
    $out += (Check-Proxy)
    $out += (Check-Env)
    return $out
}

# ============================================================
#  修复函数：返回结果（已修复 / 需重启 / 需人工处理）
# ============================================================
function Repair-Hardware {
    $a = @(Get-PhysicalAdapter)
    foreach ($ad in $a) {
        if ($ad.Status -eq 'Disabled') {
            try { Enable-NetAdapter -Name $ad.Name -Confirm:$false -ErrorAction Stop } catch {}
        }
    }
    Start-Sleep -Milliseconds 800
    foreach ($ad in $a) {
        try {
            $cur = Get-NetAdapter -Name $ad.Name -ErrorAction SilentlyContinue
            if ($cur -and $cur.Status -eq 'Down') { Restart-NetAdapter -Name $ad.Name -Confirm:$false -ErrorAction SilentlyContinue }
        } catch {}
    }
    Start-Sleep -Milliseconds 600
    if ((Get-PhysicalConnectedCount) -eq 0) {
        return '需人工处理'
    }
    return '已修复'
}

function Repair-NetConfig {
    netsh int ip reset | Out-Null
    netsh int ipv4 reset | Out-Null
    return '需重启'
}

function Repair-Dhcp {
    Set-Service Dhcp -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service Dhcp -ErrorAction SilentlyContinue
    return '已修复'
}

function Repair-Dns {
    Set-Service Dnscache -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service Dnscache -ErrorAction SilentlyContinue
    ipconfig /flushdns | Out-Null
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object {
        Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddresses -ErrorAction SilentlyContinue
    }
    return '已修复'
}

function Repair-Hosts {
    $default = @(
        '# Copyright (c) 1993-2009 Microsoft Corp.',
        '#',
        '# This is a sample HOSTS file used by Microsoft TCP/IP for Windows.',
        '#',
        '# This file contains the mappings of IP addresses to host names. Each',
        '# entry should be kept on an individual line. The IP address should',
        '# be placed in the first column followed by the corresponding host name.',
        '# The IP address and the host name should be separated by at least one',
        '# space.',
        '#',
        '# Additionally, comments (such as these) may be inserted on individual',
        '# lines or following the machine name denoted by a ''#'' symbol.',
        '#',
        '# For example:',
        '#',
        '#      102.54.94.97     rhino.acme.com          # source server',
        '#       38.25.63.10     x.acme.com              # x client host',
        '',
        '# localhost name resolution is handled within DNS itself.',
        '#	127.0.0.1       localhost',
        '#	::1             localhost',
        ''
    )
    Set-Content -LiteralPath $HostsPath -Value $default -Encoding ASCII -ErrorAction Stop
    return '已修复'
}

function Repair-Lsp {
    netsh winsock reset | Out-Null
    return '需重启'
}

function Repair-Proxy {
    # 代理存在本身不是故障：不自动关闭用户代理。
    # 代理后网络不通属代理软件/端口问题，程序不擅自改写配置，交人工处理。
    return '需人工处理'
}

function Repair-Env {
    return '需人工处理'
}

# ============================================================
#  备份 / 回滚
# ============================================================
function New-Backup {
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dir = Join-Path $script:BackupRoot $ts
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    if (Test-Path $HostsPath) { Copy-Item -LiteralPath $HostsPath -Destination (Join-Path $dir 'hosts.bak') -Force -ErrorAction SilentlyContinue }
    reg export 'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings' (Join-Path $dir 'proxy.reg') /y 2>$null | Out-Null
    $dumpFile = Join-Path $dir 'netsh_dump.txt'
    cmd /c ('netsh dump > "' + $dumpFile + '"') 2>$null | Out-Null
    $envSnap = @{
        MachinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        UserPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
        SystemRoot  = [Environment]::GetEnvironmentVariable('SystemRoot', 'Machine')
        TEMP        = [Environment]::GetEnvironmentVariable('TEMP', 'User')
        TMP         = [Environment]::GetEnvironmentVariable('TMP', 'User')
    } | ConvertTo-Json
    Set-Content -LiteralPath (Join-Path $dir 'env.json') -Value $envSnap -Encoding UTF8
    return $dir
}

function Invoke-Rollback {
    $dirs = @(Get-ChildItem -LiteralPath $script:BackupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    if ($dirs.Count -eq 0) { return '未找到备份，无法回滚' }
    $dir = $dirs[0].FullName
    $logs = @()
    $hb = Join-Path $dir 'hosts.bak'
    if (Test-Path $hb) { try { Copy-Item -LiteralPath $hb -Destination $HostsPath -Force -ErrorAction Stop; $logs += 'HOSTS 已还原' } catch {} }
    $pr = Join-Path $dir 'proxy.reg'
    if (Test-Path $pr) { reg import $pr 2>$null | Out-Null; $logs += '代理已还原' }
    $nd = Join-Path $dir 'netsh_dump.txt'
    if (Test-Path $nd) { netsh -f $nd 2>$null | Out-Null; $logs += '网络配置已还原（部分需重启）' }
    $ej = Join-Path $dir 'env.json'
    if (Test-Path $ej) {
        try {
            $s = Get-Content -LiteralPath $ej -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($s.MachinePath) { [Environment]::SetEnvironmentVariable('Path', $s.MachinePath, 'Machine') }
            if ($s.UserPath) { [Environment]::SetEnvironmentVariable('Path', $s.UserPath, 'User') }
            $logs += '环境变量已还原'
        } catch {}
    }
    if ($logs.Count -eq 0) { return '备份存在但无可还原项' }
    return ($logs -join '；')
}

# ============================================================
#  界面辅助
# ============================================================
function Write-Log {
    param([string]$msg)
    $ts = Get-Date -Format 'HH:mm:ss'
    $script:log.AppendText("[$ts] $msg`r`n")
    $script:log.SelectionStart = $script:log.TextLength
    $script:log.ScrollToCaret()
}

function Color-Rows {
    foreach ($grow in $script:grid.Rows) {
        $v = [string]$grow.Cells['状态'].Value
        $color = switch -Regex ($v) {
            '^正常$'       { [System.Drawing.Color]::LightGreen; break }
            '^异常$'       { [System.Drawing.Color]::LightCoral; break }
            '^已修复$'     { [System.Drawing.Color]::LightGreen; break }
            '需重启'       { [System.Drawing.Color]::Orange; break }
            '需人工处理'   { [System.Drawing.Color]::LightSteelBlue; break }
            '受断网影响'   { [System.Drawing.Color]::LightGray; break }
            default        { [System.Drawing.Color]::LightYellow }
        }
        $grow.Cells['状态'].Style.BackColor = $color
    }
}

function Invoke-Check {
    $script:dt.Rows.Clear()
    Write-Log '开始全面检查...'
    try {
        $script:checks = Get-CheckList
        foreach ($c in $script:checks) {
            $row = $script:dt.NewRow()
            $row['检查项'] = $c.Name
            $row['状态'] = $c.Status
            $row['说明'] = $c.Detail
            $script:dt.Rows.Add($row)
        }
        Color-Rows
        $err = @($script:checks | Where-Object { $_.Status -eq '异常' })
        Write-Log ('检查完成：共 ' + $script:checks.Count + ' 项，异常 ' + $err.Count + ' 项。')
    } catch {
        Write-Log ('检查出错：' + $_.Exception.Message)
    }
}

# ============================================================
#  主界面
# ============================================================
function Show-Gui {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = '网络检查与修复工具'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(860, 620)
    $form.MinimumSize = New-Object System.Drawing.Size(740, 480)
    $form.Font = New-Object System.Drawing.Font('Microsoft YaHei', 9)

    # 顶部按钮面板
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = 'Top'
    $panel.Height = 52

    $btnCheck = New-Object System.Windows.Forms.Button
    $btnCheck.Text = '全面检查'
    $btnCheck.Location = New-Object System.Drawing.Point(12, 10)
    $btnCheck.Size = New-Object System.Drawing.Size(110, 32)

    $btnRepair = New-Object System.Windows.Forms.Button
    $btnRepair.Text = '一键修复'
    $btnRepair.Location = New-Object System.Drawing.Point(134, 10)
    $btnRepair.Size = New-Object System.Drawing.Size(110, 32)

    $btnRollback = New-Object System.Windows.Forms.Button
    $btnRollback.Text = '回滚'
    $btnRollback.Location = New-Object System.Drawing.Point(256, 10)
    $btnRollback.Size = New-Object System.Drawing.Size(110, 32)

    $btnExit = New-Object System.Windows.Forms.Button
    $btnExit.Text = '退出'
    $btnExit.Anchor = 'Top,Right'
    $btnExit.Location = New-Object System.Drawing.Point(730, 10)
    $btnExit.Size = New-Object System.Drawing.Size(110, 32)

    $panel.Controls.Add($btnCheck)
    $panel.Controls.Add($btnRepair)
    $panel.Controls.Add($btnRollback)
    $panel.Controls.Add($btnExit)

    # 底部日志框
    $log = New-Object System.Windows.Forms.TextBox
    $log.Multiline = $true
    $log.ReadOnly = $true
    $log.ScrollBars = 'Vertical'
    $log.Dock = 'Bottom'
    $log.Height = 150
    $log.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $log.ForeColor = [System.Drawing.Color]::LightGray

    # 结果表格
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = 'Fill'
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToResizeRows = $false
    $grid.AutoSizeColumnsMode = 'None'
    $grid.SelectionMode = 'FullRowSelect'
    $grid.RowHeadersVisible = $false
    $grid.BackgroundColor = [System.Drawing.Color]::White
    $grid.EnableHeadersVisualStyles = $false
    $grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font('Microsoft YaHei', 9, [System.Drawing.FontStyle]::Bold)

    $dt = New-Object System.Data.DataTable
    [void]$dt.Columns.Add('检查项')
    [void]$dt.Columns.Add('状态')
    [void]$dt.Columns.Add('说明')

    # 手动建列：自动生成列晚于赋值会导致 Width 失效（Columns 为空），故关闭自动生成
    $grid.AutoGenerateColumns = $false
    foreach ($n in '检查项', '状态', '说明') {
        $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $col.Name = $n
        $col.HeaderText = $n
        $col.DataPropertyName = $n
        [void]$grid.Columns.Add($col)
    }
    # 检查项 / 状态 固定宽度；说明列填充剩余（窗口内除两列外的最大宽度，随窗口自适应）
    $grid.Columns['检查项'].Width = 140
    $grid.Columns['状态'].Width = 110
    $grid.Columns['说明'].AutoSizeMode = 'Fill'
    $grid.DataSource = $dt

    $form.Controls.Add($grid)
    $form.Controls.Add($log)
    $form.Controls.Add($panel)

    # 暴露到脚本作用域供事件使用
    $script:form = $form
    $script:grid = $grid
    $script:dt = $dt
    $script:log = $log

    # ---------- 事件 ----------
    $btnCheck.Add_Click({ Invoke-Check })

    $btnRepair.Add_Click({
        if (-not $script:checks) {
            [System.Windows.Forms.MessageBox]::Show('请先执行「全面检查」。', '提示', 'OK', 'Information') | Out-Null
            return
        }
        $err = @($script:checks | Where-Object { $_.Status -eq '异常' })
        if ($err.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('所有检查项均正常，无需修复。', '提示', 'OK', 'Information') | Out-Null
            return
        }
        $r = [System.Windows.Forms.MessageBox]::Show('将备份当前配置并修复 ' + $err.Count + ' 个异常项，是否继续？', '确认修复', 'YesNo', 'Question')
        if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        Write-Log '正在备份当前配置...'
        $bdir = New-Backup
        Write-Log ('备份完成：' + $bdir)

        $summary = @()
        foreach ($c in $err) {
            Write-Log ('正在修复：' + $c.Name)
            $res = switch ($c.Name) {
                '网络硬件配置' { Repair-Hardware }
                '网络连接配置' { Repair-NetConfig }
                'DHCP 服务'    { Repair-Dhcp }
                'DNS 服务'     { Repair-Dns }
                'HOSTS 文件'   { Repair-Hosts }
                'LSP 协议'     { Repair-Lsp }
                'IE 代理'      { Repair-Proxy }
                '环境变量'     { Repair-Env }
                default        { '已修复' }
            }
            foreach ($row in $script:dt.Rows) {
                if ($row['检查项'] -eq $c.Name) { $row['状态'] = $res }
            }
            $summary += ($c.Name + ' → ' + $res)
        }

        Write-Log '----- 修复汇总 -----'
        foreach ($s in $summary) { Write-Log $s }
        $reboot = @($summary | Where-Object { $_ -like '*需重启*' })
        if ($reboot.Count -gt 0) { Write-Log '提示：部分修复需重启计算机后生效。' }

        Write-Log '修复完成，正在重新检查以刷新真实状态...'
        Invoke-Check

        $tail = if ($reboot.Count -gt 0) { ' 部分项需重启生效。' } else { '' }
        [System.Windows.Forms.MessageBox]::Show(('修复完成。' + $tail + "`n`n" + ($summary -join "`n")), '完成', 'OK', 'Information') | Out-Null
    })

    $btnRollback.Add_Click({
        $r = [System.Windows.Forms.MessageBox]::Show('将回滚到最近一次备份，是否继续？', '确认回滚', 'YesNo', 'Warning')
        if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        Write-Log '正在回滚到最近一次备份...'
        $res = Invoke-Rollback
        Write-Log ('回滚结果：' + $res)
        [System.Windows.Forms.MessageBox]::Show('回滚结果：' + $res, '回滚', 'OK', 'Information') | Out-Null
    })

    $btnExit.Add_Click({ $script:form.Close() })

    # 打开时自动执行一次检查
    $form.Add_Shown({ Invoke-Check })

    $form.ShowDialog() | Out-Null
}

# ---------- 入口 ----------
Show-Gui
