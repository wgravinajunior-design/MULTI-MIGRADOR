@echo off
setlocal enabledelayedexpansion
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
REM As pastas dos migradores sao descobertas sozinhas (ver abaixo): para
REM adicionar um sistema novo basta commita-lo, nao ha lista para manter.
REM
REM Requer git e cgrc no PATH (cgrc fica em ...\Studio\37.0\bin64). NAO use
REM brcc32: nesta versao do Delphi (Studio 37) ele roda sem erro mas gera um
REM .res vazio de 32 bytes -- falha silenciosa que produziria um exe sem
REM DLLs/migradores embutidos. cgrc com o backend resinator e o que o proprio
REM msbuild do projeto ja usa para o VerInfo, entao e a ferramenta confiavel.
REM ==========================================================================
cd /d "%~dp0"

echo [1/2] Gerando migradores.zip a partir dos arquivos versionados...

REM Descobre as pastas de sistema em vez de manter uma lista fixa. Antes a
REM lista era manual e quatro migradores (CASA MAGALHAES, DIGISAT G6, HIPER e
REM ZWEB) ficaram de fora do pacote por varios releases sem ninguem notar.
REM
REM "git ls-tree -d HEAD" ja devolve so o que esta versionado, entao saidas de
REM build e pastas de ferramenta (Win32, __history, .claude, ...) nem aparecem
REM por estarem no .gitignore. A exclusao abaixo e rede de seguranca, para o
REM caso de alguma dessas pastas voltar a ser commitada por engano.
set "PASTAS="
for /f "delims=" %%D in ('git ls-tree -d --name-only HEAD') do (
  set "NOME=%%D"
  set "PULAR="
  if "!NOME:~0,1!"=="." set "PULAR=1"
  if /i "!NOME!"=="Win32"      set "PULAR=1"
  if /i "!NOME!"=="Win64"      set "PULAR=1"
  if /i "!NOME!"=="__history"  set "PULAR=1"
  if /i "!NOME!"=="__recovery" set "PULAR=1"
  if /i "!NOME!"=="log"        set "PULAR=1"
  if not defined PULAR (
    set "PASTAS=!PASTAS! "!NOME!""
    echo       + !NOME!
  )
)

if not defined PASTAS (
  echo.
  echo FALHA: nenhuma pasta de migrador encontrada no commit atual.
  goto :erro
)

git archive --format=zip -o migradores.zip HEAD --!PASTAS!
if errorlevel 1 goto :erro

echo [2/2] Compilando DllsEmbutidas.res...
cgrc -c65001 -=resinator.exe DllsEmbutidas.rc -foDllsEmbutidas.res
if errorlevel 1 goto :erro

REM Rede de seguranca contra a mesma falha silenciosa de brcc32: um .res
REM valido com os 3 recursos (LIBEAY32, SSLEAY32, MIGRADORES) tem, no minimo,
REM o tamanho do migradores.zip. Se saiu pequeno, algo ficou vazio.
for %%F in (DllsEmbutidas.res) do if %%~zF LSS 1000000 (
  echo.
  echo FALHA: DllsEmbutidas.res saiu pequeno demais ^(%%~zF bytes^). O .res nao
  echo tem as DLLs/migradores embutidos -- verifique a saida do cgrc acima.
  goto :erro
)

echo.
echo Recursos gerados com sucesso. Agora recompile o MultiMigrador.
goto :fim

:erro
echo.
echo FALHA ao gerar os recursos. Verifique se git e brcc32 estao no PATH.
exit /b 1

:fim
endlocal
