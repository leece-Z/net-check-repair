@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

rem ---- 检查管理员权限：非管理员则静默提权重启（不显示控制台） ----
net session >nul 2>&1
if %errorlevel% NEQ 0 (
    powershell -NoProfile -WindowStyle Hidden -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', ([char]34 + '%~f0' + [char]34) -Verb RunAs -WindowStyle Hidden"
    exit /b
)

rem ---- 隐藏控制台窗口启动图形界面（错误输出写入 error.log） ----
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0net_check.ps1" 2>>"%~dp0error.log"

endlocal
