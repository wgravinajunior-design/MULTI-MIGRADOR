@echo off
REM ==========================================================================
REM Regenera os recursos embutidos no MultiMigrador.exe:
REM   migradores.zip     -> pacote com todos os migradores (arquivos versionados)
REM   DllsEmbutidas.res  -> DLLs do OpenSSL + migradores.zip como recursos
REM
REM Rode este script SEMPRE que:
REM   - alterar/atualizar o exe de algum migrador (e commitar a mudanca), ou
REM   - trocar as DLLs libeay32/ssleay32.
REM Depois recompile o projeto normalmente (F9 na IDE ou msbuild).
REM
REM Requer git e brcc32 no PATH (brcc32 fica em ...\Studio\37.0\bin).
REM ==========================================================================
cd /d "%~dp0"

echo [1/2] Gerando migradores.zip a partir dos arquivos versionados...
git archive --format=zip -o migradores.zip HEAD -- "ARPA SISTEMAS" "CLOSMAQ" "DMA SISTEMAS" "EMC SOFTWARE" "GANSO SISTEMAS" "GDOOR" "LC SISTEMAS" "LINK PRO" "PROJECT 7" "QUESTOR" "RENSOFTWARE" "VTI"
if errorlevel 1 goto :erro

echo [2/2] Compilando DllsEmbutidas.res...
brcc32 DllsEmbutidas.rc
if errorlevel 1 goto :erro

echo.
echo Recursos gerados com sucesso. Agora recompile o MultiMigrador.
goto :fim

:erro
echo.
echo FALHA ao gerar os recursos. Verifique se git e brcc32 estao no PATH.

:fim
