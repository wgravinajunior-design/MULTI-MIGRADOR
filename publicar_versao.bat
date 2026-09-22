@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0publicar_versao.ps1" %*
if errorlevel 1 (
    echo.
    echo Ocorreu um erro durante a execucao do script de publicacao.
    pause
    exit /b 1
)
endlocal
