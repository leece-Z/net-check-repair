@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

rem ---- 检查管理员权限，非管理员则自提权 ----
net session >nul 2>&1
if %errorlevel% NEQ 0 (
    echo [提示] 本工具需要管理员权限，正在请求提升...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

rem ---- 启动图形界面 ----
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0net_check.ps1"

endlocal
