unit UNotificacoes;

// Notificações do Windows Toast (notification center).
// Requer Windows 10+.

interface

procedure ExibirNotificacao(const ATitulo, ACorpo: string; const ADuracao: Integer = 5000);
procedure NotificarAtualizacaoDisponivel(const AVersao: string);
procedure NotificarProblemaEnviado;

implementation

uses
  Winapi.Windows, Winapi.ShellAPI, System.SysUtils, System.IOUtils, Vcl.Forms,
  UAtualizador;

procedure ExibirNotificacao(const ATitulo, ACorpo: string; const ADuracao: Integer = 5000);
var
  HWndPai: HWND;
begin
  try
    HWndPai := Application.Handle;
    if HWndPai = 0 then
      HWndPai := GetActiveWindow;

    MessageBox(HWndPai, PChar(ACorpo), PChar(ATitulo), MB_ICONINFORMATION or MB_OK or MB_SETFOREGROUND);
  except
    // Silenciosamente ignora erros
  end;
end;

procedure NotificarAtualizacaoDisponivel(const AVersao: string);
begin
  // O dialogo seguinte (PerguntarAtualizar) mostra as notas e faz a pergunta,
  // entao aqui so anunciamos e dizemos o que vem a seguir -- sem prometer
  // "download", que da a entender que o usuario tem de baixar algo na mao.
  ExibirNotificacao(
    'Atualização disponível',
    'A versão ' + LimparVersao(AVersao) + ' do Multi Migrador já pode ser instalada.' + sLineBreak +
    sLineBreak +
    'Clique em OK para ver o que mudou e atualizar.'
  );
end;

procedure NotificarProblemaEnviado;
begin
  ExibirNotificacao(
    'Relatório enviado',
    'Seu problema foi reportado com sucesso.'
  );
end;

end.
