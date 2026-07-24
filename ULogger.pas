unit ULogger;

// Sistema de log local para rastrear ações do Multi Migrador.
// Logs são salvos em arquivo de texto na pasta do AppData (oculta ao usuário).
// Estrutura: %LOCALAPPDATA%\MultiMigrador\logs\YYYY-MM-DD.log

interface

uses
  UMigradores;

procedure LogarAcao(const ATexto: string);
procedure LogarErro(const ATexto: string);
procedure ConfigurarPastaLogs(const APastaBase: string);

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes, Winapi.Windows;

var
  FPastaLogGlobal: string = '';

function DirLogs: string;
begin
  if FPastaLogGlobal <> '' then
    Result := IncludeTrailingPathDelimiter(FPastaLogGlobal)
  else
  begin
    // Salva em %LOCALAPPDATA%\MultiMigrador\logs - pasta oculta
    Result := IncludeTrailingPathDelimiter(
      TPath.Combine(
        TPath.GetHomePath + '\AppData\Local\MultiMigrador',
        'logs'));
  end;
  ForceDirectories(Result);
end;

function ArquivoLog: string;
begin
  Result := DirLogs + FormatDateTime('yyyy-mm-dd', Now) + '.log';
end;

procedure EscreverLog(const ATexto, ATipo: string);
var
  Linha: string;
  Arquivo: string;
begin
  try
    Arquivo := ArquivoLog;
    Linha := FormatDateTime('hh:nn:ss', Now) + ' [' + ATipo + '] ' + ATexto;

    if not TFile.Exists(Arquivo) then
      TFile.WriteAllText(Arquivo, Linha + sLineBreak)
    else
      TFile.AppendAllText(Arquivo, Linha + sLineBreak);
  except
    // Silenciosamente ignora erros de log para não impactar a aplicação
  end;
end;

procedure LogarAcao(const ATexto: string);
begin
  EscreverLog(ATexto, 'INFO');
end;

procedure LogarErro(const ATexto: string);
begin
  EscreverLog(ATexto, 'ERRO');
end;

procedure ConfigurarPastaLogs(const APastaBase: string);
begin
  FPastaLogGlobal := APastaBase;
end;

end.
