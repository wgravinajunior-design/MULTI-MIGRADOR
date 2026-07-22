program HarnessUpd;
{$APPTYPE CONSOLE}
// Exercita o codigo REAL de producao (UAtualizador) sem GUI:
//  ConsultarUltimoRelease (via metodo publico VerificarAtualizacoesAsync nao;
//  aqui chamamos direto o fluxo alto nivel) e BaixarEInstalar.
uses
  System.SysUtils, UAtualizador;

var
  Info: TInfoAtualizacao;
  Erro: string;
  Concluido: Boolean;
begin
  Writeln('APP_VERSAO (embutida): ', APP_VERSAO);
  Writeln('Consultando GitHub releases/latest...');

  Concluido := False;
  VerificarAtualizacoesAsync(
    procedure(const AInfo: TInfoAtualizacao)
    begin
      Info := AInfo;
      Concluido := True;
    end);

  // espera o callback (thread)
  while not Concluido do
    Sleep(100);

  Writeln('  Sucesso consulta : ', BoolToStr(Info.Sucesso, True));
  Writeln('  Versao remota    : ', Info.VersaoRemota);
  Writeln('  Tem atualizacao  : ', BoolToStr(Info.TemAtualizacao, True));
  Writeln('  URL download     : ', Info.UrlDownload);
  Writeln;

  if Info.UrlDownload = '' then
  begin
    Writeln('Sem asset para baixar. Abortando.');
    Halt(2);
  end;

  Writeln('Baixando e instalando (troca do exe em execucao)...');
  if BaixarEInstalar(Info, Erro) then
    Writeln('  >> SUCESSO: exe substituido e changelog gravado.')
  else
  begin
    Writeln('  >> FALHA: ', Erro);
    Halt(1);
  end;
end.
