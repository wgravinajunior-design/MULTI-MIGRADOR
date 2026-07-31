unit UOrientacoes;

// Janela de orientacoes obrigatorias, mostrada antes de abrir cada migrador.
//
// O texto vem do "orientacoes.txt" da pasta do sistema -- cada migrador tem o
// seu, porque os requisitos mudam: uns precisam de servidor PostgreSQL, outros
// do driver ODBC do SQL Server, outros do Excel instalado, e a maioria nao
// precisa de nada alem do que ja vai embutido no pacote.
//
// Se a pasta nao tiver o arquivo, cai num texto padrao com os cinco cuidados
// que valem para qualquer migracao -- assim nenhum migrador abre sem aviso.
//
// Devolve True se o usuario confirmou (botao "Li e entendi").

interface

function MostrarOrientacoes(const ASistema, APastaSistema: string): Boolean;

implementation

uses
  Winapi.Windows, Winapi.ShellAPI, System.SysUtils, System.Classes, System.IOUtils,
  System.UITypes, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics,
  Vcl.ComCtrls;

type
  // Segura a URL do botao de download. Um TButton precisa de um metodo de
  // objeto no OnClick, e MostrarOrientacoes e uma funcao solta.
  TAbridorLink = class
    URL: string;
    procedure Clique(Sender: TObject);
  end;

const
  ARQ_ORIENTACOES = 'orientacoes.txt';

  ALTURA_IDEAL = 820;  // cabe o texto todo sem rolar num monitor normal
  ALTURA_MINIMA = 420; // abaixo disso o texto fica ilegivel; melhor rolar mais
  MARGEM_TELA  = 56;   // barra de titulo + folga para nao encostar na barra de tarefas

  COR_AVISO_FUNDO  = $00D7F0FB;  // amarelo claro do cabecalho
  COR_AVISO_TEXTO  = $00136A93;
  COR_FINAL_FUNDO  = $00DFF3E2;  // verde claro da mensagem final
  COR_FINAL_TEXTO  = $00246B2C;

  // Fecho da janela. Fica aqui, e nao no orientacoes.txt de cada pasta, para
  // ser igual em todos os migradores e mudar num lugar so.
  MENSAGEM_FINAL =
    'Migração boa é migração conferida.' + sLineBreak +
    'Faça o backup, teste no laboratório e valide no UPSYSTEM antes de liberar para o cliente.' + sLineBreak +
    sLineBreak +
    'Boa migração!' + sLineBreak +
    'Equipe Código Up';

  TEXTO_PADRAO =
    '!!! ATENCAO - CUIDADOS E ORIENTACOES IMPORTANTES !!!' + sLineBreak +
    sLineBreak +
    '1. AMBIENTE DE LABORATORIO / HOMOLOGACAO:' + sLineBreak +
    '   - Realize SEMPRE a migracao em ambiente de laboratorio/teste antes de aplicar na base oficial de producao.' + sLineBreak +
    '   - NUNCA execute o migrador diretamente em banco de producao com sistema em uso.' + sLineBreak +
    sLineBreak +
    '2. BACKUP OBRIGATORIO DE SEGURANCA:' + sLineBreak +
    '   - Faca backup completo das bases de Origem e Destino antes de qualquer processo.' + sLineBreak +
    sLineBreak +
    '3. VALIDACAO PREVIA E POSTERIOR DOS DADOS:' + sLineBreak +
    '   - Confira e valide os dados da base de origem antes de migrar.' + sLineBreak +
    '   - Apos a migracao, confira minuciosamente no UPSYSTEM os dados migrados.' + sLineBreak +
    sLineBreak +
    '4. CUIDADO COM AS OPCOES "APAGAR...":' + sLineBreak +
    '   - Os checkboxes "Apagar..." excluem permanentemente os registros ja migrados na base de destino. Use com extrema atencao!' + sLineBreak +
    sLineBreak +
    '5. TERMO DE RESPONSABILIDADE:' + sLineBreak +
    '   - Apos colocar em producao qualquer migracao ira apagar os dados novamente, entao confira minuciosamente os dados! A Codigo Up nao se responsabiliza por migracoes!';

procedure TAbridorLink.Clique(Sender: TObject);
begin
  // Por enquanto, apenas feedback visual. Depois integraremos com download real
  // ou link direto, conforme você decidir.
  MessageBox(0, PChar('Página de download será aberta em breve.'), PChar('Download'), MB_ICONINFORMATION or MB_OK);
end;

// Pega a primeira URL do texto de orientacoes. E ela que alimenta o botao de
// download -- so quem precisa instalar algo tem link no arquivo, entao a
// presenca da URL ja decide se o botao aparece.
function ExtrairURL(const ATexto: string): string;
var
  i, j: Integer;
begin
  Result := '';
  i := Pos('https://', ATexto);
  if i = 0 then
    i := Pos('http://', ATexto);
  if i = 0 then
    Exit;

  j := i;
  while (j <= Length(ATexto)) and (ATexto[j] > ' ') do
    Inc(j);
  Result := Copy(ATexto, i, j - i);
end;

// Le o orientacoes.txt da pasta do migrador. Encoding explicito: sem isso, um
// arquivo UTF-8 sem BOM seria lido como ANSI e os acentos sairiam quebrados.
function LerOrientacoes(const APastaSistema: string): string;
var
  Arq: string;
begin
  Result := '';
  Arq := IncludeTrailingPathDelimiter(APastaSistema) + ARQ_ORIENTACOES;
  if not TFile.Exists(Arq) then
    Exit;
  try
    Result := TFile.ReadAllText(Arq, TEncoding.UTF8);
  except
    Result := '';  // arquivo em uso ou ilegivel: usa o texto padrao
    Exit;
  end;

  // O Memo do Windows so quebra linha em #13#10. Um arquivo salvo com quebra
  // no padrao Unix (so #10) sairia todo grudado numa linha so, entao normaliza.
  Result := StringReplace(Result, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #10, sLineBreak, [rfReplaceAll]);
end;

function MostrarOrientacoes(const ASistema, APastaSistema: string): Boolean;
var
  F: TForm;
  PnTopo, PnFinal, PnBotoes, PnRodape: TPanel;
  LbTitulo, LbFinal: TLabel;
  Memo: TMemo;
  BtOk, BtCancelar, BtLink: TButton;
  Texto: string;
  Link: TAbridorLink;
  Altura: Integer;
begin
  Texto := LerOrientacoes(APastaSistema);
  if Trim(Texto) = '' then
    Texto := TEXTO_PADRAO;

  Link := TAbridorLink.Create;
  Link.URL := ExtrairURL(Texto);

  F := TForm.CreateNew(nil);
  try
    F.Caption := 'Orientacoes obrigatorias';
    F.Position := poScreenCenter;   // centrado na tela: em monitor pequeno o
                                    // centro do form principal pode jogar a
                                    // janela para fora da area visivel
    F.BorderStyle := bsDialog;
    F.ClientWidth := 620;

    // Em monitor pequeno os 820px nao cabem e os botoes ficariam fora da tela.
    // Limita a janela a area util (descontando a barra de titulo) e deixa o
    // texto rolar: o Memo e alClient e ja tem barra de rolagem vertical.
    Altura := ALTURA_IDEAL;
    if Altura > Screen.WorkAreaHeight - MARGEM_TELA then
      Altura := Screen.WorkAreaHeight - MARGEM_TELA;
    if Altura < ALTURA_MINIMA then
      Altura := ALTURA_MINIMA;
    F.ClientHeight := Altura;
    F.Font.Name := 'Segoe UI';
    F.Font.Height := -12;
    F.Color := clWhite;

    PnTopo := TPanel.Create(F);
    PnTopo.Parent := F;
    PnTopo.Align := alTop;
    PnTopo.Height := 46;
    PnTopo.BevelOuter := bvNone;
    PnTopo.Color := COR_AVISO_FUNDO;
    PnTopo.ParentBackground := False;

    LbTitulo := TLabel.Create(F);
    LbTitulo.Parent := PnTopo;
    LbTitulo.SetBounds(16, 14, 580, 20);
    LbTitulo.AutoSize := False;
    LbTitulo.Transparent := True;
    LbTitulo.Font.Style := [fsBold];
    LbTitulo.Font.Size := 11;
    LbTitulo.Font.Color := COR_AVISO_TEXTO;
    LbTitulo.Caption := 'Orientações obrigatórias — ' + ASistema;

    // Rodape num container proprio: dois paineis alBottom irmaos ficam na mao
    // da ordem de criacao para decidir quem fica embaixo, o que ja trocou a
    // mensagem de lugar uma vez. Aninhando, a posicao e explicita.
    PnRodape := TPanel.Create(F);
    PnRodape.Parent := F;
    PnRodape.Align := alBottom;
    PnRodape.Height := 160;
    PnRodape.BevelOuter := bvNone;
    PnRodape.ParentBackground := False;
    PnRodape.Color := clWhite;

    PnFinal := TPanel.Create(F);
    PnFinal.Parent := PnRodape;
    PnFinal.Align := alTop;
    PnFinal.Height := 104;
    PnFinal.BevelOuter := bvNone;
    PnFinal.Color := COR_FINAL_FUNDO;
    PnFinal.ParentBackground := False;

    LbFinal := TLabel.Create(F);
    LbFinal.Parent := PnFinal;
    LbFinal.Align := alClient;
    LbFinal.AutoSize := False;
    LbFinal.Transparent := True;
    LbFinal.WordWrap := True;
    LbFinal.Alignment := taCenter;   // centralizado na horizontal
    LbFinal.Layout := tlCenter;      // e na vertical
    LbFinal.Font.Color := COR_FINAL_TEXTO;
    LbFinal.Caption := MENSAGEM_FINAL;

    PnBotoes := TPanel.Create(F);
    PnBotoes.Parent := PnRodape;
    PnBotoes.Align := alClient;
    PnBotoes.BevelOuter := bvNone;
    PnBotoes.ParentBackground := False;
    PnBotoes.Color := clWhite;

    BtOk := TButton.Create(F);
    // Sem Anchors: a janela e bsDialog (nao redimensiona) e, como o painel dos
    // botoes e alClient, o ancoramento seria calculado antes do resize e jogaria
    // os botoes para fora da area visivel.
    BtOk.Parent := PnBotoes;
    BtOk.SetBounds(376, 10, 220, 32);
    BtOk.Caption := 'Li e entendi - abrir migrador';
    BtOk.Font.Style := [fsBold];
    BtOk.Default := True;
    BtOk.ModalResult := mrOk;

    BtCancelar := TButton.Create(F);
    BtCancelar.Parent := PnBotoes;
    BtCancelar.SetBounds(276, 10, 90, 32);
    BtCancelar.Caption := 'Cancelar';
    BtCancelar.Cancel := True;
    BtCancelar.ModalResult := mrCancel;

    // So aparece para migrador que exige instalacao (driver ODBC, PostgreSQL,
    // Excel). O link esta no texto, mas num Memo somente-leitura ele nao e
    // clicavel -- dai o botao.
    if Link.URL <> '' then
    begin
      BtLink := TButton.Create(F);
      BtLink.Parent := PnBotoes;
      BtLink.SetBounds(16, 10, 236, 32);
      BtLink.Caption := 'Abrir página de download';
      BtLink.OnClick := Link.Clique;
    end;

    Memo := TMemo.Create(F);
    Memo.Parent := F;
    Memo.Align := alClient;
    Memo.AlignWithMargins := True;
    Memo.Margins.SetBounds(16, 12, 16, 12);
    Memo.ReadOnly := True;
    Memo.ScrollBars := ssVertical;
    Memo.WordWrap := True;
    Memo.Color := clWhite;
    Memo.BorderStyle := bsNone;
    Memo.Text := Texto;
    Memo.SelStart := 0;

    Result := F.ShowModal = mrOk;
  finally
    F.Free;
    Link.Free;
  end;
end;

end.
