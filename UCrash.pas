unit UCrash;

// Sistema de tratamento de exceções e crash report.
// Captura exceções não tratadas e salva stack trace para debug.

interface

procedure ConfigurarCrashHandler;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  Vcl.Forms, Vcl.Dialogs, ULogger;

type
  TCrashHandler = class
    class procedure HandlerExcecao(Sender: TObject; E: Exception);
  end;

class procedure TCrashHandler.HandlerExcecao(Sender: TObject; E: Exception);
var
  LogArquivo: string;
  Conteudo: TStringList;
  Mensagem, NomeClasse, MsgErro: string;
begin
  try
    if E <> nil then
    begin
      NomeClasse := E.ClassName;
      MsgErro := E.Message;
    end
    else
    begin
      NomeClasse := 'Exceção Desconhecida';
      MsgErro := 'Falha não especificada ou erro de ponteiro nulo.';
    end;

    // Salva log de crash
    LogArquivo := IncludeTrailingPathDelimiter(
      TPath.GetTempPath) + 'MultiMigrador_Crash_' +
      FormatDateTime('yyyymmdd_hhnnss', Now) + '.log';

    Conteudo := TStringList.Create;
    try
      Conteudo.Add('=== CRASH REPORT ===');
      Conteudo.Add('Data: ' + FormatDateTime('dd/mm/yyyy hh:mm:ss', Now));
      Conteudo.Add('Executável: ' + ParamStr(0));
      Conteudo.Add('');
      Conteudo.Add('=== EXCEÇÃO ===');
      Conteudo.Add('Tipo: ' + NomeClasse);
      Conteudo.Add('Mensagem: ' + MsgErro);
      Conteudo.Add('');
      Conteudo.Add('=== INFORMAÇÕES DO SISTEMA ===');
      Conteudo.Add('OS: Windows');
      Conteudo.Add('Resolução: ' + IntToStr(GetSystemMetrics(SM_CXSCREEN)) + 'x' +
        IntToStr(GetSystemMetrics(SM_CYSCREEN)));

      try
        Conteudo.SaveToFile(LogArquivo, TEncoding.UTF8);
        LogarErro('CRASH: Log salvo em ' + LogArquivo);
      except
      end;
    finally
      Conteudo.Free;
    end;

    // Mostra dialog ao usuário
    Mensagem :=
      'Ocorreu um erro inesperado no Multi Migrador:' + sLineBreak + sLineBreak +
      'Tipo: ' + NomeClasse + sLineBreak +
      'Mensagem: ' + MsgErro + sLineBreak + sLineBreak +
      'Por favor, relate este erro usando "Reportar Problema" ' +
      'para que possamos corrigi-lo.';

    MessageDlg(Mensagem, mtError, [mbOK], 0);
    LogarErro('CRASH NÃO TRATADO: ' + NomeClasse + ': ' + MsgErro);
  except
  end;
end;

procedure ConfigurarCrashHandler;
begin
  Application.OnException := TCrashHandler.HandlerExcecao;
  LogarAcao('Crash handler configurado');
end;

end.
