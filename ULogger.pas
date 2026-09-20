unit ULogger;

// Sistema de log local para rastrear ações do Multi Migrador.
// Logs são salvos em arquivo de texto na pasta do AppData Local.
// Estrutura: %LOCALAPPDATA%\MultiMigrador\logs\YYYY-MM-DD.log

interface

procedure LogarAcao(const ATexto: string);
procedure LogarErro(const ATexto: string);
procedure ConfigurarPastaLogs(const APastaBase: string);
procedure LimparLogsAntigos(const ADias: Integer = 30);

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes, Winapi.Windows, System.SyncObjs;

var
  FPastaLogGlobal: string = '';
  FLogLock: TCriticalSection = nil;

function DirLogs: string;
var
  Base: string;
begin
  if FPastaLogGlobal <> '' then
    Result := IncludeTrailingPathDelimiter(FPastaLogGlobal)
  else
  begin
    Base := GetEnvironmentVariable('LOCALAPPDATA');
    if Base = '' then
      Base := TPath.GetHomePath;

    Result := IncludeTrailingPathDelimiter(
      TPath.Combine(Base, 'MultiMigrador\logs'));
  end;
  if not TDirectory.Exists(Result) then
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
  if FLogLock = nil then
    Exit;

  FLogLock.Enter;
  try
    try
      Arquivo := ArquivoLog;
      Linha := FormatDateTime('hh:nn:ss', Now) + ' [' + ATipo + '] ' + ATexto;

      if not TFile.Exists(Arquivo) then
        TFile.WriteAllText(Arquivo, Linha + sLineBreak, TEncoding.UTF8)
      else
        TFile.AppendAllText(Arquivo, Linha + sLineBreak, TEncoding.UTF8);
    except
      // Silenciosamente ignora erros para não impactar a aplicação
    end;
  finally
    FLogLock.Leave;
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
  if FLogLock <> nil then
  begin
    FLogLock.Enter;
    try
      FPastaLogGlobal := APastaBase;
    finally
      FLogLock.Leave;
    end;
  end
  else
    FPastaLogGlobal := APastaBase;
end;

procedure LimparLogsAntigos(const ADias: Integer = 30);
var
  Pasta: string;
  Arquivos: TArray<string>;
  Arq: string;
  DataLimite: TDateTime;
  DataArq: TDateTime;
begin
  try
    Pasta := DirLogs;
    if not TDirectory.Exists(Pasta) then
      Exit;

    DataLimite := Now - ADias;
    Arquivos := TDirectory.GetFiles(Pasta, '*.log', TSearchOption.soTopDirectoryOnly);
    for Arq in Arquivos do
    begin
      try
        DataArq := TFile.GetLastWriteTime(Arq);
        if DataArq < DataLimite then
          TFile.Delete(Arq);
      except
      end;
    end;
  except
  end;
end;

initialization
  FLogLock := TCriticalSection.Create;

finalization
  FreeAndNil(FLogLock);

end.
