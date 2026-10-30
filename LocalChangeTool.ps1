# ============================================================================
# 海康威视 ASMP 本地换新 批量提交工具（独立版，免安装）
# 流程: pageRmaList 拉列表 -> 逐单 getRmaDetailListPage 取详情
#       -> 改 dealResult/rebackFault/rebackFaulttext -> localChangeNewProduct 提交
# 日志: 界面实时显示；每次运行保存到 logs\localchange_时间戳.log
# 使用: 双击 Start-LocalChange.bat 或 LocalChangeTool.exe
# 安全: accesstoken 仅保存在内存中，不写入配置文件或日志（日志仅显示打码值）
# ============================================================================
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:ApiList = 'https://asmp.hikvision.com/api/sendRepairWeb/rmaManage/pageRmaList'
$script:ApiDetail = 'https://asmp.hikvision.com/api/sendRepairWeb/rmaManage/getRmaDetailListPage'
$script:ApiSub = 'https://asmp.hikvision.com/api/sendRepairWeb/loaclChange/localChangeNewProduct'
$script:AppVersion = '1.0.0'
$script:Root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($script:Root)) {
    try {
        $script:Root = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
    } catch {
        $script:Root = (Get-Location).Path
    }
}
$script:CfgPath = Join-Path $script:Root 'localchange_config.json'
$script:RecPath = Join-Path $script:Root 'localchange_records.csv'
$script:LogDir = Join-Path $script:Root 'logs'
$script:LogPath = $null
$script:StopFlag = $false
$script:rmaList = @()

# ============================ 日志 ============================
function Write-Log {
    param([string]$Msg)
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Msg
    if ($script:txtLog) {
        $script:txtLog.AppendText($line + "`r`n")
        $script:txtLog.SelectionStart = $script:txtLog.TextLength
        $script:txtLog.ScrollToCaret()
    }
    if ($script:LogPath) {
        try { [IO.File]::AppendAllText($script:LogPath, $line + "`r`n", [Text.Encoding]::UTF8) } catch {}
    }
}

# ============================ HTTP（带 header + cookie）============================
function Invoke-RmaPost {
    param([string]$Url, [string]$Token, [string]$Body)
    $res = [pscustomobject]@{ GotResp = $false; Status = 0; Text = '' }
    try {
        $req = [Net.HttpWebRequest]::Create($Url)
        $req.Method = 'POST'
        $req.ContentType = 'application/json;charset=UTF-8'
        $req.Accept = 'application/json, text/plain, */*'
        $req.Timeout = 20000
        $req.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
        $req.Headers.Add('accesstoken', $Token)
        $cc = New-Object System.Net.CookieContainer
        $ck = New-Object System.Net.Cookie('asmp_sr_token', $Token, '/', 'asmp.hikvision.com')
        $cc.Add($ck)
        $req.CookieContainer = $cc
        $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
        $req.ContentLength = $bytes.Length
        $s = $req.GetRequestStream(); $s.Write($bytes, 0, $bytes.Length); $s.Close()
        $resp = $req.GetResponse()
        $res.Status = [int]$resp.StatusCode
        $reader = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
        $res.Text = $reader.ReadToEnd(); $reader.Close(); $resp.Close()
        $res.GotResp = $true
    } catch [Net.WebException] {
        $er = $_.Exception
        $r = $er.Response
        if ($r) {
            $res.Status = [int]$r.StatusCode
            try {
                $reader = New-Object IO.StreamReader($r.GetResponseStream(), [Text.Encoding]::UTF8)
                $res.Text = $reader.ReadToEnd(); $reader.Close()
            } catch {}
            $res.GotResp = $true
        }
        if ($res.Text -eq '') { $res.Text = $er.Message }
    } catch {
        $res.GotResp = $false
        $res.Status = 0
        $res.Text = $_.Exception.Message
    }
    return $res
}

# ============================ 抓取 RMA 列表（自动翻页）============================
function Get-RmaList {
    param([string]$Token, [int]$PageSize)
    $all = New-Object System.Collections.ArrayList
    $page = 1
    $total = -1
    $totalNum = 1
    do {
        $body = '{"rmaCondition":{"rmaState":1,"rmaDetailState":10},"pageable":{"pageNum":' + $page + ',"pageSize":' + $PageSize + '}}'
        Write-Log "拉取列表 第 $page 页 请求: $body"
        $res = Invoke-RmaPost -Url $script:ApiList -Token $Token -Body $body
        if (-not $res.GotResp) {
            Write-Log "拉取列表 网络错误: $($res.Text)"
            return $null
        }
        Write-Log "拉取列表 第 $page 页 响应 HTTP $($res.Status): $($res.Text)"
        $obj = $null
        try { $obj = $res.Text | ConvertFrom-Json } catch { $obj = $null }
        if (-not $obj -or [string]$obj.code -ne '000') {
            $msg = ''
            if ($obj -and $obj.msg) { $msg = [string]$obj.msg }
            Write-Log "拉取列表 失败: code=$([string]$obj.code) msg=$msg"
            return $null
        }
        $total = [int]$obj.data.total
        $totalNum = [int]$obj.data.totalNum
        $items = @($obj.data.list)
        foreach ($it in $items) { [void]$all.Add($it) }
        Write-Log "拉取列表 第 $page 页 返回 $($items.Count) 条，累计 $($all.Count) / $total"
        if ($items.Count -eq 0) { break }
        $page++
        if ($page -gt 200) { Write-Log '页数超过安全上限(200)，停止翻页'; break }
    } while ($all.Count -lt $total)
    return $all
}

# ============================ 提交一单 ============================
function Invoke-LocalChangeOne {
    param([string]$RmaId, [string]$Token, [string]$DealResult, [string]$RebackFault, [string]$RebackFaulttext)
    $r = [pscustomobject]@{ Success = $false; SerialId = ''; Model = ''; Message = '' }
    Write-Log '----------------------------------------'
    Write-Log "RMA单号: $RmaId"

    # 1) 取详情
    $body = '{"rmaDetailCondition":{"rmaId":"' + $RmaId + '","state":10},"pageable":{"pageNum":1,"pageSize":10}}'
    Write-Log "步骤1 取详情 请求: $body"
    $res = Invoke-RmaPost -Url $script:ApiDetail -Token $Token -Body $body
    if (-not $res.GotResp) {
        Write-Log "步骤1 取详情 网络错误: $($res.Text)"
        $r.Message = '取详情网络错误: ' + $res.Text
        return $r
    }
    Write-Log "步骤1 取详情 响应 HTTP $($res.Status): $($res.Text)"
    $obj = $null
    try { $obj = $res.Text | ConvertFrom-Json } catch { $obj = $null }
    if (-not $obj -or [string]$obj.code -ne '000' -or -not $obj.data) {
        $msg = ''
        if ($obj -and $obj.msg) { $msg = [string]$obj.msg }
        Write-Log "步骤1 取详情 失败: code=$([string]$obj.code) msg=$msg"
        $r.Message = '取详情失败: ' + $msg
        return $r
    }
    $detail = $null
    if ($obj.data.list -and @($obj.data.list).Count -gt 0) {
        $detail = @($obj.data.list)[0]
    } elseif ($obj.data.PSObject.Properties['id']) {
        $detail = $obj.data
    }
    if (-not $detail) {
        Write-Log "步骤1 取详情 结果为空（该单可能已被处理）"
        $r.Message = '无详情数据（可能已被处理）'
        return $r
    }
    $r.SerialId = [string]$detail.serialId
    $r.Model = [string]$detail.productModel
    Write-Log "步骤1 取详情 成功: serialId=$($r.SerialId) 型号=$($r.Model)"

    # 2) 修改三个字段后提交
    try { $detail.dealResult = [int]$DealResult } catch { $detail.dealResult = 2 }
    $detail.rebackFault = $RebackFault
    $detail.rebackFaulttext = $RebackFaulttext
    try { $detail.ids = @([int]$detail.id) } catch {}
    $detail.isEdit = $true
    $payload = $detail | ConvertTo-Json -Depth 8
    Write-Log "步骤2 提交报文(已改 dealResult=$DealResult, rebackFault=$RebackFault, rebackFaulttext=$RebackFaulttext): $payload"

    $res = Invoke-RmaPost -Url $script:ApiSub -Token $Token -Body $payload
    if (-not $res.GotResp) {
        Write-Log "步骤2 提交 网络错误: $($res.Text)"
        $r.Message = '提交网络错误: ' + $res.Text
        return $r
    }
    Write-Log "步骤2 提交 响应 HTTP $($res.Status): $($res.Text)"
    $sub = $null
    try { $sub = $res.Text | ConvertFrom-Json } catch { $sub = $null }
    if ($sub -and [string]$sub.code -eq '000') {
        $r.Success = $true
        $r.Message = '成功'
        Write-Log '结果: 成功'
    } else {
        $msg = ''
        if ($sub -and $sub.msg) { $msg = [string]$sub.msg }
        if ($msg -eq '') { $msg = $res.Text }
        $r.Message = $msg
        Write-Log "结果: 失败 ($msg)"
    }
    return $r
}

# ============================ 提交记录 ============================
function Read-Records {
    $map = @{}
    if (Test-Path $script:RecPath) {
        try {
            $rows = Import-Csv $script:RecPath -Encoding UTF8
            foreach ($row in $rows) {
                $s = [string]$row.RMA单号
                if ($s -ne '') { $map[$s] = [string]$row.结果 }
            }
        } catch {}
    }
    return $map
}

function Add-Record {
    param([string]$RmaId, [string]$SerialId, [string]$Model, [string]$Result)
    try {
        if (-not (Test-Path $script:RecPath)) {
            [IO.File]::WriteAllText($script:RecPath, "时间,RMA单号,序列号,型号,结果`r`n", (New-Object Text.UTF8Encoding($true)))
        }
        $t = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $line = '"{0}","{1}","{2}","{3}","{4}"' -f $t, ($RmaId -replace '"', '""'), ($SerialId -replace '"', '""'), ($Model -replace '"', '""'), ($Result -replace '"', '""')
        [IO.File]::AppendAllText($script:RecPath, $line + "`r`n", [Text.Encoding]::UTF8)
    } catch {
        Write-Log "提交记录写入失败: $($_.Exception.Message)"
    }
}

# ============================ 配置读写 ============================
function Save-Config {
    try {
        $cfg = [ordered]@{
            dealResult = $txtDealResult.Text.Trim()
            rebackFault = $txtFault.Text.Trim()
            rebackFaulttext = $txtFaultText.Text.Trim()
            delay = $txtDelay.Text.Trim()
            pageSize = $txtPageSize.Text.Trim()
            skip = ([bool]$chkSkip.Checked)
        }
        $cfg | ConvertTo-Json | Set-Content -Path $script:CfgPath -Encoding UTF8
    } catch {}
}

function Load-Config {
    $cfg = $null
    if (Test-Path $script:CfgPath) {
        try { $cfg = Get-Content -Raw -Encoding UTF8 $script:CfgPath | ConvertFrom-Json } catch { $cfg = $null }
    }
    if ($cfg) {
        # 兼容旧版本配置：忽略其中可能存在的明文 token，token 必须每次手动粘贴。
        try { $txtDealResult.Text = [string]$cfg.dealResult } catch {}
        try { $txtFault.Text = [string]$cfg.rebackFault } catch {}
        try { $txtFaultText.Text = [string]$cfg.rebackFaulttext } catch {}
        try { $txtDelay.Text = [string]$cfg.delay } catch {}
        try { $txtPageSize.Text = [string]$cfg.pageSize } catch {}
        try { $chkSkip.Checked = [bool]$cfg.skip } catch {}
    }
}

# ============================ GUI ============================
$form = New-Object System.Windows.Forms.Form
$form.Text = '海康威视 ASMP 本地换新 批量提交工具 v' + $script:AppVersion
$form.Size = New-Object System.Drawing.Size(980, 720)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei', 9)

$lblToken = New-Object System.Windows.Forms.Label
$lblToken.Text = 'accesstoken（F12 -> 任意 asmp 请求标头复制；仅本次使用，不保存）:'
$lblToken.Location = New-Object System.Drawing.Point(14, 14)
$lblToken.AutoSize = $true

$txtToken = New-Object System.Windows.Forms.TextBox
$txtToken.Location = New-Object System.Drawing.Point(14, 38)
$txtToken.Size = New-Object System.Drawing.Size(936, 23)

$panelFixed = New-Object System.Windows.Forms.FlowLayoutPanel
$panelFixed.Location = New-Object System.Drawing.Point(14, 68)
$panelFixed.Size = New-Object System.Drawing.Size(936, 64)
$panelFixed.FlowDirection = 'LeftToRight'
$panelFixed.WrapContents = $true

function New-Field([string]$Label, [int]$Width, [string]$Default) {
    $p = New-Object System.Windows.Forms.Panel
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Label
    $l.AutoSize = $true
    $l.Location = New-Object System.Drawing.Point(0, 5)
    $labelWidth = [int][Math]::Ceiling($l.PreferredWidth)
    $p.Size = New-Object System.Drawing.Size(($labelWidth + $Width + 12), 26)
    $t = New-Object System.Windows.Forms.TextBox
    $t.Text = $Default
    $t.Location = New-Object System.Drawing.Point(($labelWidth + 4), 2)
    $t.Size = New-Object System.Drawing.Size($Width, 21)
    $p.Controls.Add($l) | Out-Null
    $p.Controls.Add($t) | Out-Null
    return ,$t
}
$txtDealResult = New-Field '处理结果值(dealResult):' 40 '2'
$txtFault      = New-Field '客户反映故障:' 60 '其他'
$txtFaultText  = New-Field '故障描述:' 240 '延迟高，频繁掉线，客户要求换新'
$txtDelay      = New-Field '间隔毫秒:' 50 '500'
$txtPageSize   = New-Field '每页条数:' 50 '50'

foreach ($tb in @($txtDealResult, $txtFault, $txtFaultText, $txtDelay, $txtPageSize)) {
    $panelFixed.Controls.Add($tb.Parent) | Out-Null
}

$chkSkip = New-Object System.Windows.Forms.CheckBox
$chkSkip.Text = '跳过已成功提交过的单号'
$chkSkip.Checked = $true
$chkSkip.AutoSize = $true
$panelFixed.Controls.Add($chkSkip) | Out-Null

$lblList = New-Object System.Windows.Forms.Label
$lblList.Text = 'RMA单列表（点“抓取RMA列表”填充；点选一行后可用“提交选中单号”先试一单）:'
$lblList.Location = New-Object System.Drawing.Point(14, 146)
$lblList.AutoSize = $true

$txtList = New-Object System.Windows.Forms.ListBox
$txtList.Location = New-Object System.Drawing.Point(14, 170)
$txtList.Size = New-Object System.Drawing.Size(300, 430)
$txtList.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtList.UseTabStops = $true
$txtList.HorizontalScrollbar = $true

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Both'
$txtLog.WordWrap = $false
$txtLog.Location = New-Object System.Drawing.Point(330, 170)
$txtLog.Size = New-Object System.Drawing.Size(620, 430)
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)

$script:txtLog = $txtLog

$btnFetch = New-Object System.Windows.Forms.Button
$btnFetch.Text = '抓取RMA列表'
$btnFetch.Location = New-Object System.Drawing.Point(14, 614)
$btnFetch.Size = New-Object System.Drawing.Size(100, 34)

$btnOne = New-Object System.Windows.Forms.Button
$btnOne.Text = '提交选中单号'
$btnOne.Location = New-Object System.Drawing.Point(124, 614)
$btnOne.Size = New-Object System.Drawing.Size(100, 34)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = '开始批量提交'
$btnStart.Location = New-Object System.Drawing.Point(234, 614)
$btnStart.Size = New-Object System.Drawing.Size(110, 34)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = '停止'
$btnStop.Location = New-Object System.Drawing.Point(354, 614)
$btnStop.Size = New-Object System.Drawing.Size(60, 34)

$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Text = '清空日志'
$btnClear.Location = New-Object System.Drawing.Point(424, 614)
$btnClear.Size = New-Object System.Drawing.Size(80, 34)

$btnOpenLog = New-Object System.Windows.Forms.Button
$btnOpenLog.Text = '打开日志目录'
$btnOpenLog.Location = New-Object System.Drawing.Point(514, 614)
$btnOpenLog.Size = New-Object System.Drawing.Size(100, 34)

$btnOpenRec = New-Object System.Windows.Forms.Button
$btnOpenRec.Text = '查看提交记录'
$btnOpenRec.Location = New-Object System.Drawing.Point(624, 614)
$btnOpenRec.Size = New-Object System.Drawing.Size(100, 34)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = '就绪 · v' + $script:AppVersion
$lblStatus.Location = New-Object System.Drawing.Point(740, 622)
$lblStatus.Size = New-Object System.Drawing.Size(220, 24)

$form.Controls.AddRange(@($lblToken, $txtToken, $panelFixed, $lblList, $txtList, $txtLog, $btnFetch, $btnOne, $btnStart, $btnStop, $btnClear, $btnOpenLog, $btnOpenRec, $lblStatus))

Load-Config

function New-LogFile {
    New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null
    $script:LogPath = Join-Path $script:LogDir ('localchange_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
    [IO.File]::WriteAllText($script:LogPath, '', [Text.Encoding]::UTF8)
    Write-Log ('日志文件: ' + $script:LogPath)
}

$btnFetch.Add_Click({
    $token = $txtToken.Text.Trim()
    if ($token -eq '') { Write-Log '请先填写 accesstoken'; return }
    $pageSize = 50
    if ($txtPageSize.Text.Trim() -match '^\d+$') { $pageSize = [int]$txtPageSize.Text.Trim() }
    New-LogFile
    $masked = $token
    if ($token.Length -ge 8) { $masked = $token.Substring(0, 4) + '****' + $token.Substring($token.Length - 4) }
    Write-Log ('accesstoken: ' + $masked + '（日志已打码，请求时同时带 header 和 asmp_sr_token cookie）')
    $lblStatus.Text = '正在抓取列表...'
    [System.Windows.Forms.Application]::DoEvents()
    $list = Get-RmaList -Token $token -PageSize $pageSize
    if ($null -eq $list) {
        $lblStatus.Text = '抓取失败，详见日志'
        Write-Log '抓取列表失败'
        return
    }
    $script:rmaList = @($list)
    $txtList.Items.Clear()
    foreach ($it in $script:rmaList) {
        [void]$txtList.Items.Add(('{0}`t{1}`t{2}`t{3}' -f [string]$it.rmaId, [string]$it.repairClient, [string]$it.linkman, [string]$it.createTime))
    }
    Write-Log ('共抓取 ' + $script:rmaList.Count + ' 个RMA单')
    $lblStatus.Text = "抓取完成：共 $($script:rmaList.Count) 单"
    Save-Config
})

$btnOne.Add_Click({
    $rmaId = ''
    if ($txtList.SelectedIndex -ge 0) {
        $line = [string]$txtList.SelectedItem
        if ($line -match '^\s*(DR_[A-Za-z0-9]+)') { $rmaId = $Matches[1] }
    }
    if ($rmaId -eq '') { Write-Log '请先在左侧列表点选要测试的那一行，再点本按钮'; return }
    $token = $txtToken.Text.Trim()
    if ($token -eq '') { Write-Log '请先填写 accesstoken'; return }
    $dealResult = $txtDealResult.Text.Trim()
    if ($dealResult -notmatch '^\d+$') { Write-Log '处理结果值必须是数字(默认2)'; return }
    if ([System.Windows.Forms.MessageBox]::Show("确定提交单号 $rmaId 吗？（单条测试）", '确认', 'YesNo', 'Question') -ne 'Yes') { return }
    New-LogFile
    Write-Log ('单条测试提交: ' + $rmaId)
    $r = Invoke-LocalChangeOne -RmaId $rmaId -Token $token -DealResult $dealResult -RebackFault $txtFault.Text.Trim() -RebackFaulttext $txtFaultText.Text.Trim()
    if ($r.Success) { Add-Record $rmaId $r.SerialId $r.Model '成功'; Write-Log '单条提交成功' }
    else { Add-Record $rmaId $r.SerialId $r.Model ('失败: ' + $r.Message); Write-Log ('单条提交失败: ' + $r.Message) }
    Save-Config
})

$btnStart.Add_Click({
    if ($script:rmaList.Count -eq 0) { Write-Log '请先点“抓取RMA列表”'; return }
    $token = $txtToken.Text.Trim()
    if ($token -eq '') { Write-Log '请先填写 accesstoken'; return }
    $dealResult = $txtDealResult.Text.Trim()
    if ($dealResult -notmatch '^\d+$') { Write-Log '处理结果值必须是数字(默认2)'; return }
    $fault = $txtFault.Text.Trim()
    $faultText = $txtFaultText.Text.Trim()
    $delay = 500
    if ($txtDelay.Text.Trim() -match '^\d+$') { $delay = [int]$txtDelay.Text.Trim() }
    $skipDone = $chkSkip.Checked

    New-LogFile
    $masked = $token
    if ($token.Length -ge 8) { $masked = $token.Substring(0, 4) + '****' + $token.Substring($token.Length - 4) }
    Write-Log '==================== 新的批量提交任务 ===================='
    Write-Log ('accesstoken: ' + $masked)
    Write-Log ('待提交单数: ' + $script:rmaList.Count + ' | dealResult=' + $dealResult + ' | rebackFault=' + $fault + ' | rebackFaulttext=' + $faultText + ' | 间隔=' + $delay + 'ms | 跳过已提交=' + $skipDone)

    $records = Read-Records
    $pending = @()
    foreach ($it in $script:rmaList) {
        $rid = [string]$it.rmaId
        if ($skipDone -and $records.ContainsKey($rid) -and ($records[$rid] -like '*成功*')) {
            Write-Log "跳过（此前已成功）: $rid"
        } else {
            $pending += $it
        }
    }
    if ($pending.Count -eq 0) { Write-Log '没有需要提交的单号'; $lblStatus.Text = '没有需要提交的单号'; return }
    if ([System.Windows.Forms.MessageBox]::Show("将批量提交 $($pending.Count) 个RMA单，确定继续吗？", '确认提交', 'YesNo', 'Question') -ne 'Yes') { Write-Log '用户取消'; return }

    $script:StopFlag = $false
    $btnStart.Enabled = $false
    $okCnt = 0; $failCnt = 0; $idx = 0
    foreach ($it in $pending) {
        if ($script:StopFlag) { Write-Log '用户手动停止'; break }
        $idx++
        $rid = [string]$it.rmaId
        $lblStatus.Text = "提交中 $idx / $($pending.Count) : $rid"
        [System.Windows.Forms.Application]::DoEvents()
        $r = Invoke-LocalChangeOne -RmaId $rid -Token $token -DealResult $dealResult -RebackFault $fault -RebackFaulttext $faultText
        if ($r.Success) {
            $okCnt++
            Add-Record $rid $r.SerialId $r.Model '成功'
            $records[$rid] = '成功'
        } else {
            $failCnt++
            Add-Record $rid $r.SerialId $r.Model ('失败: ' + $r.Message)
            $records[$rid] = '失败: ' + $r.Message
        }
        if ($delay -gt 0) { Start-Sleep -Milliseconds $delay }
    }
    $btnStart.Enabled = $true
    Write-Log ('==================== 任务结束：成功 ' + $okCnt + ' 单，失败 ' + $failCnt + ' 单 ====================')
    $lblStatus.Text = "完成：成功 $okCnt，失败 $failCnt"
    Save-Config
})

$btnStop.Add_Click({
    $script:StopFlag = $true
    Write-Log '收到停止指令，当前单提交完后停止...'
})

$btnClear.Add_Click({ $txtLog.Clear() })

$btnOpenLog.Add_Click({
    if (-not (Test-Path $script:LogDir)) { New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null }
    Start-Process explorer.exe $script:LogDir
})

$btnOpenRec.Add_Click({
    if (Test-Path $script:RecPath) { Start-Process notepad.exe $script:RecPath }
    else { Write-Log '还没有提交记录（提交过之后才会生成 localchange_records.csv）' }
})

$form.Add_FormClosing({ Save-Config })

$form.ShowDialog() | Out-Null
