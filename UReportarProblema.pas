unit UReportarProblema;

// Janela "Reportar Problema" do Multi Migrador.
// Monta a UI em codigo (o restante do projeto tambem cria controles em runtime),
// coleta sistema + imagens de origem/destino + descricao e dispara um e-mail via
// SMTP (Indy) em uma thread separada, com SSL implicito na porta 465.

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.UITypes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.Imaging.jpeg, Vcl.Imaging.pngimage,
  ULogger, UNotificacoes;

type
  TFormReportarProblema = class(TForm)
  private
    cbSistema: TComboBox;
    edEmail: TEdit;
    edRevenda: TEdit;
    edLinkBase: TEdit;
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
  IdAttachmentFile, IdText, IdEMailAddress, System.Win.Registry,
  UConfiguracao;

// Funções auxiliares
function EhEmailValido(const AEmail: string): Boolean;
begin
  Result := (Pos('@', AEmail) > 1) and
            (Pos('.', AEmail, Pos('@', AEmail)) > Pos('@', AEmail));
end;

function EhTemaEscuro: Boolean;
var
  Reg: TRegistry;
begin
  Result := False;
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', False) then
      try
        Result := Reg.ReadInteger('AppsUseLightTheme') = 0;
      except
        Result := False;
      end;
  finally
    Reg.Free;
  end;
end;

function SalvarDadosFormulario(const AEmail, ARevenda: string): Boolean;
var
  Reg: TRegistry;
begin
  Result := False;
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('Software\MultiMigrador', True) then
    begin
      Reg.WriteString('Email', AEmail);
      Reg.WriteString('Revenda', ARevenda);
      Result := True;
    end;
  finally
    Reg.Free;
  end;
end;

procedure CarregarDadosFormulario(out AEmail, ARevenda: string);
var
  Reg: TRegistry;
begin
  AEmail := '';
  ARevenda := '';
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('Software\MultiMigrador', False) then
    begin
      try
        AEmail := Reg.ReadString('Email');
      except
        AEmail := '';
      end;
      try
        ARevenda := Reg.ReadString('Revenda');
      except
        ARevenda := '';
      end;
    end;
  finally
    Reg.Free;
  end;
end;

const
  SMTP_REMETENTE = 'CORREÇÃO MULTI MIGRADOR';

  PLACEHOLDER = 'ORIENTAÇÕES:' + sLineBreak + sLineBreak +
    '1 - Vincule print do sistema de origem com campos e dados corretos destacados' + sLineBreak +
    '2 - Vincule print do sistema de destino com os mesmos campos e dados que estao errados e destacados' + sLineBreak +
    '3 - Coloque a base no OneDrive ou Google Drive e compartilhe o link e nos envie para analise' + sLineBreak +
    '4 - As correccoes sao liberadas ate 5 dias uteis' + sLineBreak +
    '5 - Os migradores serao atualizados automaticamente' + sLineBreak + sLineBreak +
    'Observacoes adicionais:';

  COR_TOPO_CLARO   = 5052682;    // mesmo azul do cabecalho principal
  COR_FUNDO_CLARO  = 15921906;
  COR_HINT_CLARO   = clGrayText;
  COR_TEXTO_CLARO  = $00333333;

  COR_TOPO_ESCURO   = $002A2A2A;
  COR_FUNDO_ESCURO  = $001E1E1E;
  COR_HINT_ESCURO   = $00666666;
  COR_TEXTO_ESCURO  = $00E0E0E0;

  MAX_TENTATIVAS_ENVIO = 3;

type
  // Thread de envio: mantem a UI responsiva enquanto o Indy conversa com o SMTP.
  TEnvioThread = class(TThread)
  private
    FSistema, FDescricao, FEmail, FRevenda, FLinkBase: string;
    FOrigem, FDestino: TArray<string>;
    FErro: string;
    FTentativa: Integer;
    procedure EnviarComRetry;
  protected
    procedure Execute; override;
  public
    constructor Create(const ASistema, ADescricao, AEmail, ARevenda, ALinkBase: string;
      const AOrigem, ADestino: TArray<string>);
    property Erro: string read FErro;
  end;

{ TEnvioThread }

constructor TEnvioThread.Create(const ASistema, ADescricao, AEmail, ARevenda, ALinkBase: string;
  const AOrigem, ADestino: TArray<string>);
begin
  inherited Create(True);          // criada suspensa; iniciada pelo chamador
  FreeOnTerminate := False;        // o dialogo le Erro no OnTerminate e libera
  FSistema := ASistema;
  FDescricao := ADescricao;
  FEmail := AEmail;
  FRevenda := ARevenda;
  FLinkBase := ALinkBase;
  FOrigem := AOrigem;
  FDestino := ADestino;
end;

procedure TEnvioThread.EnviarComRetry;
var
  SMTP: TIdSMTP;
  SSL: TIdSSLIOHandlerSocketOpenSSL;
  Msg: TIdMessage;
  Corpo: TIdText;
  Arq: string;
begin
  SMTP := TIdSMTP.Create(nil);
  SSL := TIdSSLIOHandlerSocketOpenSSL.Create(nil);
  Msg := TIdMessage.Create(nil);
  try
    SSL.SSLOptions.Method := sslvTLSv1_2;
    SSL.SSLOptions.SSLVersions := [sslvTLSv1_2];
    SSL.SSLOptions.Mode := sslmClient;

    SMTP.IOHandler := SSL;
    SMTP.Host := ObterSMTPHost;
    SMTP.Port := ObterSMTPPorta;
    SMTP.UseTLS := utUseImplicitTLS;
    SMTP.Username := ObterSMTPUsuario;
    SMTP.Password := ObterSMTPSenha;
    SMTP.AuthType := satDefault;
    SMTP.ConnectTimeout := 10000;
    SMTP.ReadTimeout := 15000;

    Msg.From.Address := ObterSMTPUsuario;
    Msg.From.Name := SMTP_REMETENTE;
    Msg.Recipients.EMailAddresses := ObterSMTPDestino;
    Msg.Subject := 'Correção Migrador (' + FSistema + ')';

    Corpo := TIdText.Create(Msg.MessageParts, nil);
    Corpo.ContentType := 'text/plain; charset=utf-8';
    Corpo.Body.Text :=
      'Sistema: ' + FSistema + sLineBreak +
      'E-mail: ' + FEmail + sLineBreak +
      'Revenda: ' + FRevenda + sLineBreak;

    if FLinkBase <> '' then
      Corpo.Body.Text := Corpo.Body.Text +
        'Link da Base: ' + FLinkBase + sLineBreak;

    Corpo.Body.Text := Corpo.Body.Text +
      sLineBreak + 'Observacoes:' + sLineBreak +
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

    Msg.ContentType := 'multipart/mixed';

    SMTP.Connect;
    try
      SMTP.Send(Msg);
      LogarAcao('Problema reportado: ' + FSistema);
    finally
      SMTP.Disconnect;
    end;
  finally
    Msg.Free;
    SSL.Free;
    SMTP.Free;
  end;
end;

procedure TEnvioThread.Execute;
begin
  FErro := '';
  FTentativa := 0;

  while FTentativa < MAX_TENTATIVAS_ENVIO do
  begin
    try
      Inc(FTentativa);
      EnviarComRetry;
      Exit;  // Sucesso
    except
      on E: Exception do
      begin
        FErro := E.ClassName + ': ' + E.Message;
        LogarErro('Tentativa ' + IntToStr(FTentativa) + ' falhou: ' + FErro);
        if FTentativa < MAX_TENTATIVAS_ENVIO then
          Sleep(2000 * FTentativa);  // Backoff exponencial
      end;
    end;
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
  lblTit, lblSis, lblEmail, lblRevenda, lblLinkBase, lblOri, lblDes, lblDsc: TLabel;
  btAddOri, btDelOri, btAddDes, btDelDes: TButton;
  CorTopo, CorFundo, CorTexto, CorHint: TColor;
  EmailSalvo, RevendaSalva: string;
begin
  Caption := 'Reportar Problema';
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  ClientWidth := 720;
  ClientHeight := 680;

  // Tema automático
  if EhTemaEscuro then
  begin
    CorTopo := COR_TOPO_ESCURO;
    CorFundo := COR_FUNDO_ESCURO;
    CorTexto := COR_TEXTO_ESCURO;
    CorHint := COR_HINT_ESCURO;
  end
  else
  begin
    CorTopo := COR_TOPO_CLARO;
    CorFundo := COR_FUNDO_CLARO;
    CorTexto := COR_TEXTO_CLARO;
    CorHint := COR_HINT_CLARO;
  end;

  Color := CorFundo;
  Font.Name := 'Segoe UI';
  Font.Height := -12;

  // Carrega dados salvos anteriormente
  CarregarDadosFormulario(EmailSalvo, RevendaSalva);

  // Cabecalho
  Topo := TPanel.Create(Self);
  Topo.Parent := Self;
  Topo.Align := alTop;
  Topo.Height := 56;
  Topo.BevelOuter := bvNone;
  Topo.ParentBackground := False;
  Topo.Color := CorTopo;

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
  lblSis.Caption := 'Sistema *';
  lblSis.Font.Style := [fsBold];
  lblSis.Font.Color := CorTexto;

  cbSistema := TComboBox.Create(Self);
  cbSistema.Parent := Self;
  cbSistema.SetBounds(20, 92, 680, 24);
  cbSistema.Style := csDropDownList;
  if Assigned(ASistemas) then
    cbSistema.Items.Assign(ASistemas);
  if cbSistema.Items.Count > 0 then
    cbSistema.ItemIndex := 0;

  // E-mail
  lblEmail := TLabel.Create(Self);
  lblEmail.Parent := Self;
  lblEmail.SetBounds(20, 128, 200, 15);
  lblEmail.Caption := 'E-mail *';
  lblEmail.Font.Style := [fsBold];
  lblEmail.Font.Color := CorTexto;

  edEmail := TEdit.Create(Self);
  edEmail.Parent := Self;
  edEmail.SetBounds(20, 146, 330, 24);
  edEmail.Text := EmailSalvo;

  // Revenda
  lblRevenda := TLabel.Create(Self);
  lblRevenda.Parent := Self;
  lblRevenda.SetBounds(370, 128, 330, 15);
  lblRevenda.Caption := 'Nome da Revenda *';
  lblRevenda.Font.Style := [fsBold];
  lblRevenda.Font.Color := CorTexto;

  edRevenda := TEdit.Create(Self);
  edRevenda.Parent := Self;
  edRevenda.SetBounds(370, 146, 330, 24);
  edRevenda.Text := RevendaSalva;

  // Link da Base de Migracao
  lblLinkBase := TLabel.Create(Self);
  lblLinkBase.Parent := Self;
  lblLinkBase.SetBounds(20, 180, 680, 15);
  lblLinkBase.Caption := 'Link da Base de Migracao (OneDrive / Google Drive)';
  lblLinkBase.Font.Style := [fsBold];
  lblLinkBase.Font.Color := CorTexto;

  edLinkBase := TEdit.Create(Self);
  edLinkBase.Parent := Self;
  edLinkBase.SetBounds(20, 198, 680, 24);

  // Imagens de ORIGEM
  lblOri := TLabel.Create(Self);
  lblOri.Parent := Self;
  lblOri.SetBounds(20, 240, 320, 15);
  lblOri.Caption := 'Imagens do sistema de ORIGEM';
  lblOri.Font.Style := [fsBold];
  lblOri.Font.Color := CorTexto;

  lbOrigem := TListBox.Create(Self);
  lbOrigem.Parent := Self;
  lbOrigem.SetBounds(20, 258, 250, 96);

  btAddOri := TButton.Create(Self);
  btAddOri.Parent := Self;
  btAddOri.SetBounds(278, 258, 74, 26);
  btAddOri.Caption := 'Importar...';
  btAddOri.OnClick := ImportarOrigemClick;

  btDelOri := TButton.Create(Self);
  btDelOri.Parent := Self;
  btDelOri.SetBounds(278, 288, 74, 26);
  btDelOri.Caption := 'Remover';
  btDelOri.Tag := 1; // origem
  btDelOri.OnClick := RemoverImagemClick;

  // Imagens de DESTINO
  lblDes := TLabel.Create(Self);
  lblDes.Parent := Self;
  lblDes.SetBounds(380, 240, 320, 15);
  lblDes.Caption := 'Imagens do sistema de DESTINO (campos errados)';
  lblDes.Font.Style := [fsBold];
  lblDes.Font.Color := CorTexto;

  lbDestino := TListBox.Create(Self);
  lbDestino.Parent := Self;
  lbDestino.SetBounds(380, 258, 250, 96);

  btAddDes := TButton.Create(Self);
  btAddDes.Parent := Self;
  btAddDes.SetBounds(638, 258, 62, 26);
  btAddDes.Caption := 'Importar';
  btAddDes.OnClick := ImportarDestinoClick;

  btDelDes := TButton.Create(Self);
  btDelDes.Parent := Self;
  btDelDes.SetBounds(638, 288, 62, 26);
  btDelDes.Caption := 'Remover';
  btDelDes.Tag := 2; // destino
  btDelDes.OnClick := RemoverImagemClick;

  // Descricao livre com placeholder (marca d'agua)
  lblDsc := TLabel.Create(Self);
  lblDsc.Parent := Self;
  lblDsc.SetBounds(20, 366, 300, 15);
  lblDsc.Caption := 'Observacoes';
  lblDsc.Font.Style := [fsBold];
  lblDsc.Font.Color := CorTexto;

  mDescricao := TMemo.Create(Self);
  mDescricao.Parent := Self;
  mDescricao.SetBounds(20, 384, 680, 160);
  mDescricao.ScrollBars := ssVertical;
  mDescricao.WordWrap := True;
  mDescricao.OnEnter := MemoEnter;
  mDescricao.OnExit := MemoExit;
  // Estado inicial: marca d'agua em cinza
  FPlaceholderAtivo := True;
  mDescricao.Font.Color := CorHint;
  mDescricao.Text := PLACEHOLDER;

  // Rodape
  lblStatus := TLabel.Create(Self);
  lblStatus.Parent := Self;
  lblStatus.SetBounds(20, 592, 480, 40);
  lblStatus.AutoSize := False;
  lblStatus.WordWrap := True;
  lblStatus.Caption := '';

  btEnviar := TButton.Create(Self);
  btEnviar.Parent := Self;
  btEnviar.SetBounds(520, 624, 90, 32);
  btEnviar.Caption := 'Enviar';
  btEnviar.Default := True;
  btEnviar.OnClick := EnviarClick;

  btCancelar := TButton.Create(Self);
  btCancelar.Parent := Self;
  btCancelar.SetBounds(616, 624, 84, 32);
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
    mDescricao.Font.Color := COR_TEXTO_CLARO;
  end;
end;

procedure TFormReportarProblema.MemoExit(Sender: TObject);
begin
  if Trim(mDescricao.Text) = '' then
  begin
    FPlaceholderAtivo := True;
    mDescricao.Font.Color := COR_HINT_CLARO;
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
  Descricao, Email, Revenda, LinkBase: string;
  Thread: TEnvioThread;
begin
  if cbSistema.ItemIndex < 0 then
  begin
    DefinirStatus('Selecione o sistema.', True);
    cbSistema.SetFocus;
    Exit;
  end;

  Email := Trim(edEmail.Text);
  if Email = '' then
  begin
    DefinirStatus('Informe o E-mail.', True);
    edEmail.SetFocus;
    Exit;
  end;

  if not EhEmailValido(Email) then
  begin
    DefinirStatus('E-mail inválido. Use o formato: exemplo@dominio.com', True);
    edEmail.SetFocus;
    Exit;
  end;

  Revenda := Trim(edRevenda.Text);
  if Revenda = '' then
  begin
    DefinirStatus('Informe o Nome da Revenda.', True);
    edRevenda.SetFocus;
    Exit;
  end;

  SalvarDadosFormulario(Email, Revenda);

  LinkBase := Trim(edLinkBase.Text);

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
  lblStatus.Font.Color := clBlue;

  // Envio em thread para nao travar a janela.
  Thread := TEnvioThread.Create(cbSistema.Text, Descricao, Email, Revenda, LinkBase, Origem, Destino);
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
    NotificarProblemaEnviado;
    MessageDlg('Relatorio enviado com sucesso para ' + ObterSMTPDestino + '.',
      mtInformation, [mbOK], 0);
    ModalResult := mrOk;
  end
  else
  begin
    DefinirStatus('Falha ao enviar: ' + Erro, True);
    LogarErro('Falha ao enviar relatório: ' + Erro);
    MessageDlg('Nao foi possivel enviar o relatorio:'#13#10 + Erro +
      #13#10#13#10'O relatório será retentado automaticamente.',
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
