<#
.SYNOPSIS
    FPGA Space Invaders 项目环境自检脚本。

.DESCRIPTION
    检查本项目所需的全部工具是否就绪：Git、Python(含图像库)、Node.js、
    VS Code、Vivado/Vitis。输出 PASS/WARN/FAIL 表格，并以退出码返回结果
    （0 = 全部必需项通过；1 = 存在必需项失败）。

    依据：docs/environment_setup.md

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\check_env.ps1
#>

[CmdletBinding()]
param(
    # Vivado 安装根目录（可覆盖）
    [string]$VivadoRoot = 'D:\fpga\2026.1',
    # VS Code 可执行文件路径（可覆盖）
    [string]$VsCodeExe  = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe"
)

$ErrorActionPreference = 'Continue'
$script:results = @()

function Add-Result {
    param(
        [string]$Name,
        [string]$Status,   # PASS / WARN / FAIL
        [string]$Detail,
        [switch]$Required
    )
    $script:results += [pscustomobject]@{
        Name     = $Name
        Status   = $Status
        Detail   = $Detail
        Required = [bool]$Required
    }
}

function Get-CmdPath {
    param([string]$Name)
    $c = Get-Command $Name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source } else { return $null }
}

Write-Host ''
Write-Host '==============================================================' -ForegroundColor Cyan
Write-Host '  FPGA Space Invaders - 环境自检 (Phase 0)' -ForegroundColor Cyan
Write-Host '==============================================================' -ForegroundColor Cyan

# --- OS -----------------------------------------------------------------
$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
if ($os) {
    Add-Result -Name 'Windows' -Status 'PASS' -Detail ("{0} (Build {1})" -f $os.Caption.Trim(), $os.BuildNumber)
} else {
    Add-Result -Name 'Windows' -Status 'WARN' -Detail '无法读取系统信息'
}

# --- Git ----------------------------------------------------------------
$git = Get-CmdPath 'git'
if ($git) {
    $v = (& git --version) 2>&1
    Add-Result -Name 'Git' -Status 'PASS' -Detail ("{0} | {1}" -f $v, $git) -Required
} else {
    Add-Result -Name 'Git' -Status 'FAIL' -Detail '未找到 git，请安装 https://git-scm.com/download/win' -Required
}

# --- Python -------------------------------------------------------------
# 注意：Windows 上的 python.exe 可能是 Microsoft Store 的占位程序（返回码 1 且无输出）。
# 本项目统一使用 py launcher 或虚拟环境中的 python.exe。
$pyLauncher = Get-CmdPath 'py'
$pyExe      = $null
if ($pyLauncher) {
    $pyExe = (& py -3 -c "import sys;print(sys.executable)") 2>&1
    if ($LASTEXITCODE -eq 0) {
        $pyVer = (& py -3 -c "import sys;print('.'.join(map(str,sys.version_info[:3])))") 2>&1
        Add-Result -Name 'Python' -Status 'PASS' -Detail ("{0} | {1}" -f $pyVer, $pyExe) -Required
    } else {
        Add-Result -Name 'Python' -Status 'FAIL' -Detail 'py launcher 存在但无法启动 Python 3' -Required
        $pyExe = $null
    }
} else {
    Add-Result -Name 'Python' -Status 'FAIL' -Detail '未找到 py launcher，请安装 Python 3.11+' -Required
}

# 提醒：python 命令是否为 Store 占位程序
$pythonCmd = Get-CmdPath 'python'
if ($pythonCmd -and $pythonCmd -like '*WindowsApps*') {
    Add-Result -Name 'python 命令' -Status 'WARN' -Detail 'python 指向 Microsoft Store 占位程序，请改用 py 或 .venv\Scripts\python.exe'
}

# --- Python 图像处理库 ---------------------------------------------------
if ($pyExe) {
    $probe = 'import importlib,sys
mods = {"numpy":"numpy","cv2":"opencv-python","scipy":"scipy","matplotlib":"matplotlib","PIL":"pillow","skimage":"scikit-image"}
missing = []
ok = []
for mod, pkg in mods.items():
    try:
        m = importlib.import_module(mod)
        ok.append("{0}=={1}".format(pkg, getattr(m, "__version__", "?")))
    except Exception:
        missing.append(pkg)
print("OK:" + ",".join(ok))
print("MISSING:" + ",".join(missing))
'
    $probeFile = Join-Path $env:TEMP 'fpga_env_probe.py'
    [System.IO.File]::WriteAllText($probeFile, $probe, (New-Object System.Text.UTF8Encoding($false)))
    $out = (& py -3 $probeFile) 2>&1
    $okLine  = ($out | Where-Object { $_ -like 'OK:*' })      -replace '^OK:', ''
    $badLine = ($out | Where-Object { $_ -like 'MISSING:*' })  -replace '^MISSING:', ''
    if ([string]::IsNullOrWhiteSpace($badLine)) {
        Add-Result -Name 'Python 图像库' -Status 'PASS' -Detail ("已安装: {0}" -f $okLine) -Required
    } else {
        Add-Result -Name 'Python 图像库' -Status 'FAIL' -Detail ("缺少: {0}  ->  运行 py -m pip install -r requirements.txt" -f $badLine) -Required
    }
    Remove-Item -LiteralPath $probeFile -ErrorAction SilentlyContinue
}

# --- Node.js ------------------------------------------------------------
$node = Get-CmdPath 'node'
if ($node) {
    $v = (& node --version) 2>&1
    Add-Result -Name 'Node.js' -Status 'PASS' -Detail ("{0} | {1}" -f $v, $node)
} else {
    Add-Result -Name 'Node.js' -Status 'WARN' -Detail '未找到 node（仅 web-game 原型需要，非必需）'
}

# --- VS Code ------------------------------------------------------------
$codeExe = Get-CmdPath 'code'
if (-not $codeExe -and (Test-Path -LiteralPath $VsCodeExe)) { $codeExe = $VsCodeExe }
if ($codeExe) {
    $v = (Get-Item -LiteralPath $codeExe).VersionInfo.ProductVersion
    if (-not $v) { $v = 'unknown' }
    Add-Result -Name 'VS Code' -Status 'PASS' -Detail ("VS Code {0} | {1}" -f $v, $codeExe) -Required
} else {
    Add-Result -Name 'VS Code' -Status 'FAIL' -Detail '未安装 -> winget install --id Microsoft.VisualStudioCode --scope user' -Required
}

# --- Vivado -------------------------------------------------------------
$vivadoBat = Join-Path $VivadoRoot 'Vivado\bin\vivado.bat'
$vivadoCmd = Get-CmdPath 'vivado'
if ($vivadoCmd) {
    Add-Result -Name 'Vivado' -Status 'PASS' -Detail ("已在 PATH: {0}" -f $vivadoCmd) -Required
} elseif (Test-Path -LiteralPath $vivadoBat) {
    $verTxt = Split-Path -Leaf (Resolve-Path -LiteralPath $VivadoRoot).Path
    Add-Result -Name 'Vivado' -Status 'WARN' -Detail ("已安装但未加入 PATH: {0} [安装版本 {1}] -> 执行 {2}" -f $vivadoBat, $verTxt, (Join-Path $VivadoRoot 'Vivado\bin\settings64.bat')) -Required
} else {
    Add-Result -Name 'Vivado' -Status 'FAIL' -Detail ("未在 {0} 找到 Vivado" -f $VivadoRoot) -Required
}

# --- Vitis HLS ----------------------------------------------------------
$vitisBat = Join-Path $VivadoRoot 'Vitis\bin\vitis.bat'
$vitisHls = Join-Path $VivadoRoot 'Vitis\bin\vitis_hls.bat'
if ((Test-Path -LiteralPath $vitisBat) -or (Test-Path -LiteralPath $vitisHls)) {
    Add-Result -Name 'Vitis / HLS' -Status 'PASS' -Detail '已安装' -Required
} else {
    Add-Result -Name 'Vitis / HLS' -Status 'WARN' -Detail '未找到 Vitis；B 开发 HLS 前必须安装'
}

# --- 目标器件 / 板卡 ------------------------------------------------------
Add-Result -Name '目标器件' -Status 'WARN' -Detail '尚未冻结，见 docs/interface_spec.md 第 2 节（第 1 周内必须关闭）'

# --- 输出 ---------------------------------------------------------------
Write-Host ''
Write-Host '检查结果:' -ForegroundColor White
Write-Host ('-' * 78)

$script:results | Format-Table -AutoSize -Property @(
    @{ L = '检查项'; E = { $_.Name } },
    @{ L = '状态'; E = {
            switch ($_.Status) {
                'PASS' { 'PASS' }
                'WARN' { 'WARN' }
                default { 'FAIL' }
            }
        }
    },
    @{ L = '详情'; E = { $_.Detail } }
) | Out-String -Width 200 | Write-Host

foreach ($r in $script:results) {
    $color = switch ($r.Status) { 'PASS' { 'Green' } 'WARN' { 'Yellow' } default { 'Red' } }
    Write-Host ("[{0}] {1}: {2}" -f $r.Status, $r.Name, $r.Detail) -ForegroundColor $color
}

$failed = @($script:results | Where-Object { $_.Status -eq 'FAIL' -and $_.Required })
Write-Host ''
if ($failed.Count -eq 0) {
    Write-Host '环境自检通过：必需项全部就绪。' -ForegroundColor Green
    exit 0
} else {
    Write-Host ("环境自检失败：{0} 个必需项未就绪。" -f $failed.Count) -ForegroundColor Red
    exit 1
}