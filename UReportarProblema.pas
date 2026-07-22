unit UReportarProblema;

// Janela "Reportar Problema" do Multi Migrador.
// Monta a UI em codigo (o restante do projeto tambem cria controles em runtime),
// coleta sistema + imagens de origem/destino + descricao e dispara um e-mail via
// SMTP (Indy) em uma thread separada, com SSL implicito na porta 465.

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.UITypes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.Imaging.jpeg, Vcl.Imaging.pngimage;

type
  TFormReportarProblema = class(TForm)
  private
    cbSistema: TComboBox;
    lbOrigem: TListBox;
    lbDestino: TListBox;
    mDescricao: TMemo;
    btEnviar: TButton;
    btCancelar: TButton;
    lblStatus: TLabel;
    FPlaceholderAtivo: Boolean;
    procedure MontarUI(const ASistemas: TStrings);
    procedure ImportarOrigemClick(Sender: TObject);
    procedure ImportarDestinoClick(Sender: TObject);
    procedure RemoverImagemClick(Sender: TObject);
    procedure EnviarClick(Sender: TObject);
    procedure MemoEnter(Sender: TObject);
    procedure MemoExit(Sender: TObject);
    procedure AdicionarImagens(ALista: TListBox);
    procedure DefinirStatus(const ATexto: string; AErro: Boolean);
    procedure EnvioConcluido(Sender: TObject);
  public
    constructor CriarComSistemas(AOwner: TComponent; const ASistemas: TStrings);
  end;

// Abre o dialogo modal ja preenchido com a lista de sistemas do projeto.
procedure MostrarReportarProblema(const ASistemas: TStrings);

implementation

uses
  IdSMTP, IdMessage, IdSSLOpenSSL, IdExplicitTLSClientServerBase,
  IdAttachmentFile, IdText, IdEMailAddress;

const
  SMTP_HOST      = 'smtp.titan.email';
  SMTP_PORTA     = 465;
  SMTP_USUARIO   = 'migracao@goupsistemas.com';
  SMTP_SENHA     = 'Goup226457#$';
  SMTP_DESTINO   = 'migracao@goupsistemas.com';
  SMTP_ASSUNTO   = 'Correcao Multi Migrador';

  PLACEHOLDER = 'Faca upload das imagens do sistema de origem marcando os campos ' +
    'necessarios e do sistema de destino com os campos que estao errados.';

  COR_TOPO   = 5052682;    // mesmo azul do cabecalho principal
  COR_FUNDO  = 15921906;
  COR_HINT   = clGrayText;
  COR_TEXTO  = $00333333;

type
  // Thread de envio: mantem a UI responsiva enquanto o Indy conversa com o SMTP.
  TEnvioThread = class(TThread)
  private
    FSistema, FDescricao: string;
    FOrigem, FDestino: TArray<string>;
    FErro: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const ASistema, ADescricao: string;
      const AOrigem, ADestino: TArray<string>);
    property Erro: string read FErro;
  end;

{ TEnvioThread }

constructor TEnvioThread.Create(const ASistema, ADescricao: string;
  const AOrigem, ADestino: TArray<string>);
begin
  inherited Create(True);          // criada suspensa; iniciada pelo chamador
  FreeOnTerminate := False;        // o dialogo le Erro no OnTerminate e libera
  FSistema := ASistema;
  FDescricao := ADescricao;
  FOrigem := AOrigem;
  FDestino := ADestino;
end;

procedure TEnvioThread.Execute;
var
  SMTP: TIdSMTP;
  SSL: TIdSSLIOHandlerSocketOpenSSL;
  Msg: TIdMessage;
  Corpo: TIdText;
  Arq: string;
begin
  FErro := '';
  SMTP := TIdSMTP.Create(nil);
  SSL := TIdSSLIOHandlerSocketOpenSSL.Create(nil);
  Msg := TIdMessage.Create(nil);
  try
    // --- Transporte seguro (TLS) sobre conexao segura (SSL implicito na 465) ---
    SSL.SSLOptions.Method := sslvTLSv1_2;
    SSL.SSLOptions.SSLVersions := [sslvTLSv1_2];
    SSL.SSLOptions.Mode := sslmClient;

    SMTP.IOHandler := SSL;
    SMTP.Host := SMTP_HOST;
    SMTP.Port := SMTP_PORTA;
    SMTP.UseTLS := utUseImplicitTLS;      // 465 = SSL desde o handshake
    SMTP.Username := SMTP_USUARIO;
    SMTP.Password := SMTP_SENHA;
    SMTP.AuthType := satDefault;

    // --- Monta a mensagem ---
    Msg.From.Address := SMTP_USUARIO;
    Msg.From.Name := 'Multi Migrador';
    Msg.Recipients.EMailAddresses := SMTP_DESTINO;
    Msg.Subject := SMTP_ASSUNTO + ' - ' + FSistema;

    Corpo := TIdText.Create(Msg.MessageParts, nil);
    Corpo.ContentType := 'text/plain; charset=utf-8';
    Corpo.Body.Text :=
      'Sistema: ' + FSistema + sLineBreak + sLineBreak +
      'Descricao do problema:' + sLineBreak +
      FDescricao + sLineBreak + sLineBreak +
      'Imagens do sistema de ORIGEM: ' + IntToStr(Length(FOrigem)) + sLineBreak +
      'Imagens do sistema de DESTINO: ' + IntToStr(Length(FDestino)) + sLineBreak;

    for Arq in FOrigem do
      if FileExists(Arq) then
        with TIdAttachmentFile.Create(Msg.MessageParts, Arq) do
          FileName := 'ORIGEM_' + ExtractFileName(Arq);

    for Arq in FDestino do
      if FileExists(Arq) then
        with TIdAttachmentFile.Create(Msg.MessageParts, Arq) do
          FileName := 'DESTINO_' + ExtractFileName(Arq);

    // O corpo deve ser tratado como parte principal do multipart.
    Msg.ContentType := 'multipart/mixed';

    try
      SMTP.Connect;
      try
        SMTP.Send(Msg);
      finally
        SMTP.Disconnect;
      end;
    except
      on E: Exception do
        FErro := E.ClassName + ': ' + E.Message;
    end;
  finally
    Msg.Free;
    SSL.Free;
    SMTP.Free;
  end;
end;

{ TFormReportarProblema }

constructor TFormReportarProblema.CriarComSistemas(AOwner: TComponent;
  const ASistemas: TStrings);
begin
  inherited CreateNew(AOwner);
  MontarUI(ASistemas);
end;

procedure TFormReportarProblema.MontarUI(const ASistemas: TStrings);
var
  Topo: TPanel;
  lblTit, lblSis, lblOri, lblDes, lblDsc: TLabel;
  btAddOri, btDelOri, btAddDes, btDelDes: TButton;
begin
  Caption := 'Reportar Problema';
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  ClientWidth := 720;
  ClientHeight := 560;
  Color := COR_FUNDO;
  Font.Name := 'Segoe UI';
  Font.Height := -12;

  // Cabecalho
  Topo := TPanel.Create(Self);
  Topo.Parent := Self;
  Topo.Align := alTop;
  Topo.Height := 56;
  Topo.BevelOuter := bvNone;
  Topo.ParentBackground := False;
  Topo.Color := COR_TOPO;

  lblTit := TLabel.Create(Self);
  lblTit.Parent := Topo;
  lblTit.SetBounds(20, 14, 300, 28);
  lblTit.Caption := 'Reportar Problema';
  lblTit.Font.Color := clWhite;
  lblTit.Font.Height := -19;
  lblTit.Font.Style := [fsBold];
  lblTit.Transparent := True;

  // Sistema
  lblSis := TLabel.Create(Self);
  lblSis.Parent := Self;
  lblSis.SetBounds(20, 74, 200, 15);
  lblSis.Caption := 'Sistema';
  lblSis.Font.Style := [fsBold];
  lblSis.Font.Color := COR_TEXTO;

  cbSistema := TComboBox.Create(Self);
  cbSistema.Parent := Self;
  cbSistema.SetBounds(20, 92, 680, 24);
  cbSistema.Style := csDropDownList;
  if Assigned(ASistemas) then
    cbSistema.Items.Assign(ASistemas);
  if cbSistema.Items.Count > 0 then
    cbSistema.ItemIndex := 0;

  // Imagens de ORIGEM
  lblOri := TLabel.Create(Self);
  lblOri.Parent := Self;
  lblOri.SetBounds(20, 128, 320, 15);
  lblOri.Caption := 'Imagens do sistema de ORIGEM';
  lblOri.Font.Style := [fsBold];
  lblOri.Font.Color := COR_TEXTO;

  lbOrigem := TListBox.Create(Self);
  lbOrigem.Parent := Self;
  lbOrigem.SetBounds(20, 146, 250, 96);

  btAddOri := TButton.Create(Self);
  btAddOri.Parent := Self;
  btAddOri.SetBounds(278, 146, 74, 26);
  btAddOri.Caption := 'Importar...';
  btAddOri.OnClick := ImportarOrigemClick;

  btDelOri := TButton.Create(Self);
  btDelOri.Parent := Self;
  btDelOri.SetBounds(278, 176, 74, 26);
  btDelOri.Caption := 'Remover';
  btDelOri.Tag := 1; // origem
  btDelOri.OnClick := RemoverImagemClick;

  // Imagens de DESTINO
  lblDes := TLabel.Create(Self);
  lblDes.Parent := Self;
  lblDes.SetBounds(380, 128, 320, 15);
  lblDes.Caption := 'Imagens do sistema de DESTINO (campos errados)';
  lblDes.Font.Style := [fsBold];
  lblDes.Font.Color := COR_TEXTO;

  lbDestino := TListBox.Create(Self);
  lbDestino.Parent := Self;
  lbDestino.SetBounds(380, 146, 250, 96);

  btAddDes := TButton.Create(Self);
  btAddDes.Parent := Self;
  btAddDes.SetBounds(638, 146, 62, 26);
  btAddDes.Caption := 'Importar';
  btAddDes.OnClick := ImportarDestinoClick;

  btDelDes := TButton.Create(Self);
  btDelDes.Parent := Self;
  btDelDes.SetBounds(638, 176, 62, 26);
  btDelDes.Caption := 'Remover';
  btDelDes.Tag := 2; // destino
  btDelDes.OnClick := RemoverImagemClick;

  // Descricao livre com placeholder (marca d'agua)
  lblDsc := TLabel.Create(Self);
  lblDsc.Parent := Self;
  lblDsc.SetBounds(20, 254, 300, 15);
  lblDsc.Caption := 'Descricao';
  lblDsc.Font.Style := [fsBold];
  lblDsc.Font.Color := COR_TEXTO;

  mDescricao := TMemo.Create(Self);
  mDescricao.Parent := Self;
  mDescricao.SetBounds(20, 272, 680, 190);
  mDescricao.ScrollBars := ssVertical;
  mDescricao.WordWrap := True;
  mDescricao.OnEnter := MemoEnter;
  mDescricao.OnExit := MemoExit;
  // Estado inicial: marca d'agua em cinza
  FPlaceholderAtivo := True;
  mDescricao.Font.Color := COR_HINT;
  mDescricao.Text := PLACEHOLDER;

  // Rodape
  lblStatus := TLabel.Create(Self);
  lblStatus.Parent := Self;
  lblStatus.SetBounds(20, 480, 480, 40);
  lblStatus.AutoSize := False;
  lblStatus.WordWrap := True;
  lblStatus.Caption := '';

  btEnviar := TButton.Create(Self);
  btEnviar.Parent := Self;
  btEnviar.SetBounds(520, 512, 90, 32);
  btEnviar.Caption := 'Enviar';
  btEnviar.Default := True;
  btEnviar.OnClick := EnviarClick;

  btCancelar := TButton.Create(Self);
  btCancelar.Parent := Self;
  btCancelar.SetBounds(616, 512, 84, 32);
  btCancelar.Caption := 'Cancelar';
  btCancelar.Cancel := True;
  btCancelar.ModalResult := mrCancel;
end;

procedure TFormReportarProblema.MemoEnter(Sender: TObject);
begin
  if FPlaceholderAtivo then
  begin
    FPlaceholderAtivo := False;
    mDescricao.Clear;
    mDescricao.Font.Color := COR_TEXTO;
  end;
end;

procedure TFormReportarProblema.MemoExit(Sender: TObject);
begin
  if Trim(mDescricao.Text) = '' then
  begin
    FPlaceholderAtivo := True;
    mDescricao.Font.Color := COR_HINT;
    mDescricao.Text := PLACEHOLDER;
  end;
end;

procedure TFormReportarProblema.AdicionarImagens(ALista: TListBox);
var
  Dlg: TOpenDialog;
  Arq: string;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := 'Selecione as imagens';
    Dlg.Filter := 'Imagens (*.png;*.jpg;*.jpeg;*.bmp;*.gif)|*.png;*.jpg;*.jpeg;*.bmp;*.gif|Todos os arquivos (*.*)|*.*';
    Dlg.Options := Dlg.Options + [ofAllowMultiSelect, ofFileMustExist];
    if Dlg.Execute then
      for Arq in Dlg.Files do
        if ALista.Items.IndexOf(Arq) < 0 then
          ALista.Items.Add(Arq);
  finally
    Dlg.Free;
  end;
end;

procedure TFormReportarProblema.ImportarOrigemClick(Sender: TObject);
begin
  AdicionarImagens(lbOrigem);
end;

procedure TFormReportarProblema.ImportarDestinoClick(Sender: TObject);
begin
  AdicionarImagens(lbDestino);
end;

procedure TFormReportarProblema.RemoverImagemClick(Sender: TObject);
var
  Lista: TListBox;
begin
  if TButton(Sender).Tag = 1 then
    Lista := lbOrigem
  else
    Lista := lbDestino;
  if Lista.ItemIndex >= 0 then
    Lista.Items.Delete(Lista.ItemIndex);
end;

procedure TFormReportarProblema.DefinirStatus(const ATexto: string; AErro: Boolean);
begin
  lblStatus.Caption := ATexto;
  if AErro then
    lblStatus.Font.Color := $004040FF
  else
    lblStatus.Font.Color := clGreen;
  lblStatus.Update;
end;

procedure TFormReportarProblema.EnviarClick(Sender: TObject);
var
  i: Integer;
  Origem, Destino: TArray<string>;
  Descricao: string;
  Thread: TEnvioThread;
begin
  if cbSistema.ItemIndex < 0 then
  begin
    DefinirStatus('Selecione o sistema.', True);
    cbSistema.SetFocus;
    Exit;
  end;

  if FPlaceholderAtivo then
    Descricao := ''
  else
    Descricao := Trim(mDescricao.Text);

  if Descricao = '' then
  begin
    DefinirStatus('Descreva o problema no campo de texto.', True);
    mDescricao.SetFocus;
    Exit;
  end;

  SetLength(Origem, lbOrigem.Items.Count);
  for i := 0 to lbOrigem.Items.Count - 1 do
    Origem[i] := lbOrigem.Items[i];

  SetLength(Destino, lbDestino.Items.Count);
  for i := 0 to lbDestino.Items.Count - 1 do
    Destino[i] := lbDestino.Items[i];

  btEnviar.Enabled := False;
  btCancelar.Enabled := False;
  Screen.Cursor := crHourGlass;
  DefinirStatus('Enviando e-mail, aguarde...', False);
  lblStatus.Font.Color := COR_TEXTO;

  // Envio em thread para nao travar a janela.
  Thread := TEnvioThread.Create(cbSistema.Text, Descricao, Origem, Destino);
  Thread.OnTerminate := EnvioConcluido;
  Thread.Start;
end;

procedure TFormReportarProblema.EnvioConcluido(Sender: TObject);
var
  Erro: string;
begin
  Erro := TEnvioThread(Sender).Erro;
  Screen.Cursor := crDefault;
  btEnviar.Enabled := True;
  btCancelar.Enabled := True;

  if Erro = '' then
  begin
    DefinirStatus('Relatorio enviado com sucesso!', False);
    MessageDlg('Relatorio enviado com sucesso para ' + SMTP_DESTINO + '.',
      mtInformation, [mbOK], 0);
    ModalResult := mrOk;
  end
  else
  begin
    DefinirStatus('Falha ao enviar: ' + Erro, True);
    MessageDlg('Nao foi possivel enviar o relatorio:'#13#10 + Erro,
      mtError, [mbOK], 0);
  end;
end;

procedure MostrarReportarProblema(const ASistemas: TStrings);
var
  Frm: TFormReportarProblema;
begin
  Frm := TFormReportarProblema.CriarComSistemas(Application, ASistemas);
  try
    Frm.ShowModal;
  finally
    Frm.Free;
  end;
end;

end.
