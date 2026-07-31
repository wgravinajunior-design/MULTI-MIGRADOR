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
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics;

const
  ARQ_ORIENTACOES = 'orientacoes.txt';

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
  BtOk, BtCancelar: TButton;
  Texto: string;
begin
  Texto := LerOrientacoes(APastaSistema);
  if Trim(Texto) = '' then
    Texto := TEXTO_PADRAO;

  F := TForm.CreateNew(nil);
  try
    F.Caption := 'Orientacoes obrigatorias';
    F.Position := poMainFormCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 620;
    F.ClientHeight := 700;
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
  end;
end;

end.
