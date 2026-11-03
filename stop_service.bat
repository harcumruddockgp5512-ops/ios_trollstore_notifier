@echo off
title 停止异动做空雷达服务
cd /d "%~dp0"

echo 正在停止 15926 端口及 FRP 穿透进程...
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":15926 " ^| findstr "LISTENING"') do (
    taskkill /f /pid %%a >nul 2>&1
)
taskkill /f /im frpc.exe >nul 2>&1

echo 服务已完全停止。
timeout /t 2 >nul
