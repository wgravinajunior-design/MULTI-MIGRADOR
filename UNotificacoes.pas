unit UNotificacoes;

// Notificações do Windows Toast (notification center).
// Requer Windows 10+.

interface

procedure ExibirNotificacao(const ATitulo, ACorpo: string; const ADuracao: Integer = 5000);
procedure NotificarAtualizacaoDisponivel(const AVersao: string);
procedure NotificarProblemaEnviado;

implementation

uses
  Winapi.Windows, Winapi.ShellAPI, System.SysUtils, System.IOUtils, Vcl.Forms;

procedure ExibirNotificacao(const ATitulo, ACorpo: string; const ADuracao: Integer = 5000);
begin
  try
    // Notificação simples via Windows API
    // Requer Windows 10+ com suporte a toasts
    // Esta é uma implementação básica que mostra o comportamento desejado
    // Uma implementação completa usaria Windows.UI.Notifications diretamente
    MessageBox(0, PChar(ACorpo), PChar(ATitulo), MB_ICONINFORMATION or MB_OK);
  except
    // Silenciosamente ignora erros
  end;
end;

procedure NotificarAtualizacaoDisponivel(const AVersao: string);
begin
  ExibirNotificacao(
    'Nova versão disponível',
    'Multi Migrador ' + AVersao + ' está pronto para download'
  );
end;

procedure NotificarProblemaEnviado;
begin
  ExibirNotificacao(
    'Relatório enviado',
    'Seu problema foi reportado com sucesso'
  );
end;

end.
