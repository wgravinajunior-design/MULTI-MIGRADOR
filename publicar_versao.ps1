# ==============================================================================
# publicar_versao.ps1
#
# Automatiza o ciclo completo de release do Multi Migrador:
#  1. Valida ferramentas necessarias (git, Delphi msbuild, rc.exe, gh)
#  2. Bump da versao em UAtualizador.pas (UTF-8 com BOM), MultiMigrador.dproj e .migradores.ver
#  3. Commita migradores e alteracoes pendentes (o git archive requer arquivos no HEAD)
#  4. Executa gerar_recursos.bat (gera migradores.zip e DllsEmbutidas.res)
#  5. Compila MultiMigrador.exe via MSBuild (Release Win32)
#  6. Valida tamanho do binario e calcula hash SHA256
#  7. Commita o bump e cria a tag vX.Y.Z
#  8. Envia para o GitHub (git push + gh release create anexando MultiMigrador.exe)
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Versao,

    [Parameter(Position=1)]
    [string]$Notas,

    [switch]$SkipPush,
    [switch]$SkipRelease
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# Garante PATH com Delphi, Git e GitHub CLI
$DelphiBin = "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin"
$DelphiBin64 = "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin64"
$GitCmd = "C:\Program Files\Git\cmd"
$GhBin = "C:\Program Files\GitHub CLI"

foreach ($p in @($DelphiBin, $DelphiBin64, $GitCmd, $GhBin)) {
    if ((Test-Path $p) -and ($env:PATH -notlike "*$p*")) {
        $env:PATH = "$p;$env:PATH"
    }
}

function Write-Step {
    param([string]$Msg)
    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host ">> $Msg" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Msg)
    Write-Host " [OK] $Msg" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Msg)
    Write-Host " [AVISO] $Msg" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Msg)
    Write-Host " [ERRO] $Msg" -ForegroundColor Red
}

# ------------------------------------------------------------------------------
# 1. Validacao de Ferramentas
# ------------------------------------------------------------------------------
Write-Step "1. Validando ferramentas necessarias..."

$GitExe = Get-Command "git" -ErrorAction SilentlyContinue
if (-not $GitExe) {
    throw "Git nao encontrado no PATH. Instale o Git ou ajuste o PATH."
}
Write-Ok "Git: $($GitExe.Source)"

$RcExe = Get-Command "rc" -ErrorAction SilentlyContinue
if (-not $RcExe) {
    throw "Compilador de recursos rc.exe nao encontrado em $DelphiBin."
}
Write-Ok "Resource Compiler: $($RcExe.Source)"

$RsVars = Join-Path $DelphiBin "rsvars.bat"
if (-not (Test-Path $RsVars)) {
    throw "rsvars.bat nao encontrado em $RsVars."
}
Write-Ok "Delphi rsvars: $RsVars"

# ------------------------------------------------------------------------------
# 1.1 Checagem de BOM UTF-8 nos fontes (.pas/.dpr)
# ------------------------------------------------------------------------------
Write-Step "1.1. Verificando BOM UTF-8 nos arquivos .pas/.dpr..."

$ArquivosSemBom = Get-ChildItem *.pas,*.dpr | ForEach-Object {
    $Bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    if ($Bytes.Length -lt 3 -or $Bytes[0] -ne 0xEF -or $Bytes[1] -ne 0xBB -or $Bytes[2] -ne 0xBF) {
        $_.FullName
    }
}

if ($ArquivosSemBom) {
    Write-Warn "Arquivos sem BOM UTF-8 encontrados (acentos ficariam corrompidos no exe). Corrigindo automaticamente:"
    $Utf8BomFix = New-Object System.Text.UTF8Encoding($true)
    foreach ($Arquivo in $ArquivosSemBom) {
        $Conteudo = [System.IO.File]::ReadAllText($Arquivo, [System.Text.Encoding]::UTF8)
        [System.IO.File]::WriteAllText($Arquivo, $Conteudo, $Utf8BomFix)
        Write-Host "  - BOM adicionado: $(Split-Path -Leaf $Arquivo)"
    }
    Write-Ok "Todos os arquivos .pas/.dpr agora estao em UTF-8 com BOM."
} else {
    Write-Ok "Todos os arquivos .pas/.dpr ja estao em UTF-8 com BOM."
}

# ------------------------------------------------------------------------------
# 2. Determinacao da Versao e Notas
# ------------------------------------------------------------------------------
Write-Step "2. Determinando versao e notas..."

$AtualizadorPath = Join-Path $ScriptDir "UAtualizador.pas"
$AtualizadorConteudo = [System.IO.File]::ReadAllText($AtualizadorPath, [System.Text.Encoding]::UTF8)

if ($AtualizadorConteudo -match "APP_VERSAO\s*=\s*'([^']+)'") {
    $VersaoAtual = $Matches[1]
} else {
    throw "Nao foi possivel extrair APP_VERSAO de UAtualizador.pas"
}

Write-Host "Versao atual no codigo: $VersaoAtual"

if (-not $Versao) {
    $Partes = $VersaoAtual.Split('.')
    if ($Partes.Length -ge 3) {
        $Patch = [int]$Partes[2] + 1
        $Versao = "$($Partes[0]).$($Partes[1]).$Patch"
    } else {
        $Versao = "$VersaoAtual.1"
    }
    Write-Host "Nova versao sugerida: $Versao"
}

# Detecta quais pastas de migrador tiveram arquivos alterados desde a ultima tag,
# para listar "Atualizacao migrador <Nome>" nas notas do release automaticamente.
$UltimaTag = & git describe --tags --abbrev=0 2>$null
$MigradoresAtualizados = @()
if ($LASTEXITCODE -eq 0 -and $UltimaTag) {
    $ArquivosAlterados = & git diff --name-only "$UltimaTag" HEAD
    $ArquivosStaged = & git diff --name-only --cached
    $ArquivosPendentes = & git status --porcelain | ForEach-Object { $_.Substring(3) }
    $TodosArquivos = @($ArquivosAlterados) + @($ArquivosStaged) + @($ArquivosPendentes) | Where-Object { $_ }

    $MigradoresAtualizados = $TodosArquivos |
        Where-Object { $_ -match '^([^/\\]+)[/\\]' -and (Test-Path (Split-Path $_ -Parent) -PathType Container) -and (Get-Item (Split-Path $_ -Parent) -Force).PSIsContainer } |
        ForEach-Object { ($_ -split '[/\\]')[0] } |
        Where-Object { (Test-Path (Join-Path $ScriptDir $_) -PathType Container) -and ($_ -notmatch '^(Win32|__history)$') } |
        Sort-Object -Unique
}

if (-not $Notas) {
    if ($MigradoresAtualizados.Count -gt 0) {
        $LinhasMigradores = $MigradoresAtualizados | ForEach-Object { "- Atualizacao migrador $_" }
        $Notas = "Atualizacao e melhorias da versao v$Versao`r`n`r`n" + ($LinhasMigradores -join "`r`n")
    } else {
        $Notas = "Atualizacao e melhorias da versao v$Versao"
    }
}

Write-Ok "Versao alvo: $Versao"
if ($MigradoresAtualizados.Count -gt 0) {
    Write-Ok "Migradores atualizados detectados: $($MigradoresAtualizados -join ', ')"
}
Write-Ok "Notas: $Notas"

# ------------------------------------------------------------------------------
# 3. Commitar alteracoes de migradores/codigo pendentes ANTES do git archive
# ------------------------------------------------------------------------------
Write-Step "3. Verificando alteracoes pendentes para empacotamento..."

# O git archive precisa que os arquivos estejam commitados no HEAD.
$GitStatus = & git status --porcelain
if ($GitStatus) {
    Write-Host "Alteracoes detectadas antes do build:"
    Write-Host ($GitStatus | Out-String)
    Write-Host "Adicionando e commitando alteracoes de migradores e configuracoes..."
    & git add -A
    & git commit -m "Melhorias e atualizacao de migradores para v$Versao"
    Write-Ok "Alteracoes commitadas com sucesso."
} else {
    Write-Ok "Repositorio limpo, nenhuma alteracao pendente."
}

# ------------------------------------------------------------------------------
# 4. Bump de versao nos arquivos
# ------------------------------------------------------------------------------
Write-Step "4. Aplicando bump de versao ($Versao)..."

$PartesVersao = $Versao.Split('.')
$Major = if ($PartesVersao.Length -ge 1) { $PartesVersao[0] } else { "1" }
$Minor = if ($PartesVersao.Length -ge 2) { $PartesVersao[1] } else { "0" }
$Release = if ($PartesVersao.Length -ge 3) { $PartesVersao[2] } else { "0" }
$Build = if ($PartesVersao.Length -ge 4) { $PartesVersao[3] } else { "0" }
$VersaoQuad = "$Major.$Minor.$Release.$Build"

# 4.1. UAtualizador.pas (obrigatorio UTF-8 com BOM)
$Utf8WithBom = New-Object System.Text.UTF8Encoding($true)
$NovoAtualizador = [System.Text.RegularExpressions.Regex]::Replace(
    $AtualizadorConteudo,
    "APP_VERSAO\s*=\s*'[^']+'",
    "APP_VERSAO   = '$Versao'"
)
[System.IO.File]::WriteAllText($AtualizadorPath, $NovoAtualizador, $Utf8WithBom)
Write-Ok "UAtualizador.pas atualizado com UTF-8 BOM."

# 4.2. MultiMigrador.dproj
$DprojPath = Join-Path $ScriptDir "MultiMigrador.dproj"
$DprojConteudo = [System.IO.File]::ReadAllText($DprojPath, [System.Text.Encoding]::UTF8)

$DprojConteudo = [System.Text.RegularExpressions.Regex]::Replace($DprojConteudo, "<VerInfo_MajorVer>\d+</VerInfo_MajorVer>", "<VerInfo_MajorVer>$Major</VerInfo_MajorVer>")
$DprojConteudo = [System.Text.RegularExpressions.Regex]::Replace($DprojConteudo, "<VerInfo_MinorVer>\d+</VerInfo_MinorVer>", "<VerInfo_MinorVer>$Minor</VerInfo_MinorVer>")
$DprojConteudo = [System.Text.RegularExpressions.Regex]::Replace($DprojConteudo, "<VerInfo_Release>\d+</VerInfo_Release>", "<VerInfo_Release>$Release</VerInfo_Release>")
$DprojConteudo = [System.Text.RegularExpressions.Regex]::Replace($DprojConteudo, "<VerInfo_Build>\d+</VerInfo_Build>", "<VerInfo_Build>$Build</VerInfo_Build>")
$DprojConteudo = [System.Text.RegularExpressions.Regex]::Replace($DprojConteudo, "FileVersion=[\d\.]+", "FileVersion=$VersaoQuad")
$DprojConteudo = [System.Text.RegularExpressions.Regex]::Replace($DprojConteudo, "ProductVersion=[\d\.]+", "ProductVersion=$VersaoQuad")
[System.IO.File]::WriteAllText($DprojPath, $DprojConteudo, [System.Text.Encoding]::UTF8)
Write-Ok "MultiMigrador.dproj atualizado com versao $VersaoQuad."

# 4.3. .migradores.ver (se existir, limpa atributo hidden antes de sobrescrever)
$VerPath = Join-Path $ScriptDir ".migradores.ver"
if (Test-Path $VerPath) {
    (Get-Item $VerPath -Force).Attributes = [System.IO.FileAttributes]::Normal
}
[System.IO.File]::WriteAllText($VerPath, $Versao, [System.Text.Encoding]::ASCII)
Write-Ok ".migradores.ver atualizado."

# ------------------------------------------------------------------------------
# 5. Gerar Recursos Embutidos (migradores.zip e DllsEmbutidas.res)
# ------------------------------------------------------------------------------
Write-Step "5. Gerando recursos embutidos (gerar_recursos.bat)..."

cmd.exe /c ".\gerar_recursos.bat"
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao gerar recursos embutidos (codigo $LASTEXITCODE)."
}

$ResFile = Join-Path $ScriptDir "DllsEmbutidas.res"
if (-not (Test-Path $ResFile)) {
    throw "DllsEmbutidas.res nao foi gerado."
}
$ResSize = (Get-Item $ResFile).Length
if ($ResSize -lt 10000000) {
    throw "DllsEmbutidas.res ficou pequeno demais ($ResSize bytes). Abortando."
}
Write-Ok "DllsEmbutidas.res gerado com sucesso: $([math]::Round($ResSize / 1MB, 2)) MB."

# ------------------------------------------------------------------------------
# 6. Compilar MultiMigrador.exe com Delphi MSBuild (Release)
# ------------------------------------------------------------------------------
Write-Step "6. Compilando MultiMigrador.exe via MSBuild (Release)..."

$BuildCmd = "call `"$RsVars`" && msbuild MultiMigrador.dproj /p:Config=Release /t:Build"
cmd.exe /c $BuildCmd
if ($LASTEXITCODE -ne 0) {
    throw "Falha na compilacao do MultiMigrador.dproj via MSBuild."
}

$ExePath = Join-Path $ScriptDir "MultiMigrador.exe"
if (-not (Test-Path $ExePath)) {
    throw "MultiMigrador.exe nao foi encontrado na raiz apos a compilacao."
}

$ExeSize = (Get-Item $ExePath).Length
if ($ExeSize -lt 100000000) {
    throw "MultiMigrador.exe ficou com tamanho menor que 100 MB ($ExeSize bytes). Os recursos podem nao ter sido embutidos."
}
Write-Ok "MultiMigrador.exe compilado com sucesso: $([math]::Round($ExeSize / 1MB, 2)) MB."

# ------------------------------------------------------------------------------
# 7. Calcular Hash SHA256 do Executavel
# ------------------------------------------------------------------------------
Write-Step "7. Calculando hash SHA256 do executavel..."

$Sha256 = (Get-FileHash -Path $ExePath -Algorithm SHA256).Hash.ToLower()
Write-Ok "SHA256: $Sha256"

# ------------------------------------------------------------------------------
# 8. Commitar bump de versao e criar Tag Git
# ------------------------------------------------------------------------------
Write-Step "8. Criando commit e tag Git..."

$Tag = "v$Versao"

& git add -u
& git commit -m "$($Tag): $Notas"
& git tag -a $Tag -m "$($Tag): $Notas"

Write-Ok "Commit e tag $Tag criados com sucesso."

# ------------------------------------------------------------------------------
# 9. Envio para o GitHub (Push e Release)
# ------------------------------------------------------------------------------
if ($SkipPush) {
    Write-Warn "Parametro -SkipPush ativo. Concluido sem enviar ao GitHub."
    return
}

Write-Step "9. Enviando alteracoes e tags para o GitHub..."

& git push origin main
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao dar git push origin main."
}
& git push origin $Tag
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao dar git push origin $Tag."
}
Write-Ok "Push de main e tag $Tag concluidos."

if ($SkipRelease) {
    Write-Warn "Parametro -SkipRelease ativo. Release do GitHub nao sera criado."
    return
}

Write-Step "10. Publicando Release no GitHub..."

$LinhasCorpo = @(
    $Notas,
    "",
    "### Integridade do Binario",
    "- **Arquivo:** MultiMigrador.exe",
    "- **SHA256:** $Sha256"
)
$CorpoRelease = $LinhasCorpo -join "`r`n"

$GhExe = Get-Command "gh" -ErrorAction SilentlyContinue
$GhAutenticado = $false

if ($GhExe) {
    $GhStatusOut = (& gh auth status 2>&1 | Out-String)
    if ($LASTEXITCODE -eq 0) {
        $GhAutenticado = $true
    }
}

if ($GhAutenticado) {
    Write-Host "Criando release via GitHub CLI..."
    & gh release create $Tag $ExePath --title $Tag --notes "$CorpoRelease"
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Release $Tag criado e MultiMigrador.exe anexado com sucesso!"
    } else {
        Write-Warn "gh release create retornou erro. Verifique a conexao ou permissoes."
    }
} else {
    Write-Warn "GitHub CLI nao esta autenticada com 'gh auth login'."
    Write-Host "Para anexar o executavel ao release:"
    Write-Host "1. Execute: gh auth login"
    Write-Host "2. Em seguida: gh release create $Tag `"$ExePath`" --title `"$Tag`" --notes `"$CorpoRelease`""
    Write-Host "Ou crie o release manualmente em: https://github.com/wgravinajunior-design/MULTI-MIGRADOR/releases/new"
}

Write-Step "PROCESSO DE RELEASE CONCLUIDO COM SUCESSO!"
Write-Ok "Versao: $Tag"
Write-Ok "Exe: $ExePath ($([math]::Round($ExeSize / 1MB, 2)) MB)"
Write-Ok "SHA256: $Sha256"
