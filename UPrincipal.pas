unit UPrincipal;

interface

uses
  Winapi.Windows, Winapi.ShellAPI, System.SysUtils, System.Classes, System.IOUtils,
  System.UITypes, System.Generics.Collections, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Imaging.pngimage, Vcl.Imaging.jpeg,
  UReportarProblema, UAtualizador, UMigradores, ULogger, UNotificacoes,
  System.Win.Registry, UCrash;

type
  TFormPrincipal = class(TForm)
    PanelTopo: TPanel;
    ImageLogo: TImage;
    LabelTitulo: TLabel;
    LabelSub: TLabel;
    LabelBuild: TLabel;
    ScrollBox: TScrollBox;
    FlowCards: TFlowPanel;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FExes: TStringList;
    FSistemas: TStringList;
    FBtReportar: TButton;
    FEdFiltro: TEdit;
    FLblNovoVersao: TLabel;
    FMapaCards: TDictionary<string, TPanel>;
    function PastaBase: string;
    function LocalizarExecutavel(const ADir: string): string;
    procedure CarregarSistemas;
    procedure CriarCard(const ANome, ACaminho: string);
    procedure CardClick(Sender: TObject);
    procedure CardMouseEnter(Sender: TObject);
    procedure CardMouseLeave(Sender: TObject);
    procedure ReportarProblemaClick(Sender: TObject);
    procedure AtualizacaoVerificada(const AInfo: TInfoAtualizacao);
    procedure FiltroMudou(Sender: TObject);
    procedure AtualizarVisibilidadeCards;
    procedure ConfigurarTema;
    procedure KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  end;

var
  FormPrincipal: TFormPrincipal;

implementation

{$R *.dfm}

const
  // Paleta moderna e limpa
  COR_CARD        = clWhite;
  COR_HOVER       = $00F8F9FA;
  COR_BORDA       = $00E0E0E0;
  COR_BORDA_HOVER = $004A90E2;  // Azul moderno
  COR_SOMBRA      = $00D6D6D6;
  COR_ACENTO      = $004A90E2;  // Azul para hover

  COR_CARD_ESCURO        = $002A2A2A;
  COR_HOVER_ESCURO       = $00353535;
  COR_BORDA_ESCURO       = $00404040;
  COR_BORDA_HOVER_ESCURO = $004A90E2;
  COR_SOMBRA_ESCURO      = $001A1A1A;

  COR_FUNDO_PRINCIPAL    = $00FAFBFC;
  COR_FUNDO_ESCURO       = $001E1E1E;

procedure TFormPrincipal.FormCreate(Sender: TObject);
var
  ExePath: string;
  BuildDate: TDateTime;
  W, H: Integer;
begin
  FExes := TStringList.Create;
  FSistemas := TStringList.Create;
  FMapaCards := TDictionary<string, TPanel>.Create;

  ConfigurarTema;
  ConfigurarCrashHandler;  // Configura tratamento de exceções

  // Campo de Filtro - dentro da barra azul
  FEdFiltro := TEdit.Create(Self);
  FEdFiltro.Parent := PanelTopo;
  FEdFiltro.SetBounds(20, 50, 400, 28);
  FEdFiltro.Font.Size := 10;
  FEdFiltro.Font.Name := 'Segoe UI';
  FEdFiltro.TextHint := 'Buscar sistema...';
  FEdFiltro.OnChange := FiltroMudou;
  FEdFiltro.OnKeyDown := KeyDown;
  FEdFiltro.BorderStyle := bsSingle;

  // Label para notificação de nova versão - na barra azul
  FLblNovoVersao := TLabel.Create(Self);
  FLblNovoVersao.Parent := PanelTopo;
  FLblNovoVersao.SetBounds(440, 50, 350, 28);
  FLblNovoVersao.Font.Style := [fsBold];
  FLblNovoVersao.Font.Color := $00FFD700;
  FLblNovoVersao.Font.Size := 10;
  FLblNovoVersao.Alignment := taLeftJustify;
  FLblNovoVersao.Layout := tlCenter;
  FLblNovoVersao.Caption := '';
  FLblNovoVersao.Visible := False;

  // Botão "Reportar Problema" no canto direito do cabeçalho
  FBtReportar := TButton.Create(Self);
  FBtReportar.Parent := PanelTopo;
  FBtReportar.SetBounds(PanelTopo.Width - 190, 50, 170, 28);
  FBtReportar.Anchors := [akTop, akRight];
  FBtReportar.Caption := 'REPORTAR PROBLEMA';
  FBtReportar.Font.Style := [fsBold];
  FBtReportar.OnClick := ReportarProblemaClick;

  // Atalhos globais da janela
  Self.OnKeyDown := KeyDown;

  // Abre maximizado (tela cheia). O tamanho abaixo e o que a janela assume ao
  // ser restaurada pelo usuario -- sem ele, restaurar deixaria a janela no
  // tamanho de design do formulario.
  W := Screen.WorkAreaWidth div 2;
  H := Screen.WorkAreaHeight div 2;
  if W < 900 then W := 900;
  if H < 620 then H := 620;

  Width := W;
  Height := H;
  Left := (Screen.WorkAreaWidth - Width) div 2;
  Top := (Screen.WorkAreaHeight - Height) div 2;

  WindowState := wsMaximized;

  // Exibe a data de build com base na ultima modificacao do executavel principal
  ExePath := ParamStr(0);
  if TFile.Exists(ExePath) then
  begin
    BuildDate := TFile.GetLastWriteTime(ExePath);
    LabelBuild.Caption := 'Build: ' + FormatDateTime('dd/mm/yyyy hh:nn', BuildDate);
  end
  else
    LabelBuild.Caption := 'Build: --';

  // Mostra a versao atual do app ao lado da data de build.
  LabelBuild.Caption := 'v' + APP_VERSAO + '  |  ' + LabelBuild.Caption;

  CarregarSistemas;

  // Limpeza pos-atualizacao + exibe o changelog da versao recem-instalada.
  ProcessarStartup;

  // Verifica no GitHub se ha versao mais nova (em background, sem travar a UI).
  VerificarAtualizacoesAsync(AtualizacaoVerificada);
end;

procedure TFormPrincipal.AtualizacaoVerificada(const AInfo: TInfoAtualizacao);
var
  Erro: string;
begin
  if not AInfo.Sucesso then
  begin
    LogarErro('Falha ao verificar atualizações: ' + AInfo.Erro);
    Exit;
  end;

  if not AInfo.TemAtualizacao then
    Exit;

  NotificarAtualizacaoDisponivel(AInfo.VersaoRemota);

  FLblNovoVersao.Caption := '🔔 Nova versão ' + AInfo.VersaoRemota + ' disponível!';
  FLblNovoVersao.Visible := True;
  LogarAcao('Nova versão disponível: ' + AInfo.VersaoRemota);

  if not PerguntarAtualizar(AInfo) then
    Exit;

  if BaixarEInstalar(AInfo, Erro) then
  begin
    LogarAcao('Atualizado para versão ' + AInfo.VersaoRemota);
    MessageDlg('Atualização baixada. O sistema será reiniciado na nova versão.',
      mtInformation, [mbOK], 0);
    ReiniciarApp;
    Application.Terminate;
  end
  else
  begin
    LogarErro('Falha ao baixar/instalar atualização: ' + Erro);
    MessageDlg('Não foi possível atualizar:'#13#10 + Erro, mtError, [mbOK], 0);
  end;
end;

procedure TFormPrincipal.FormDestroy(Sender: TObject);
begin
  FExes.Free;
  FSistemas.Free;
  FMapaCards.Free;
end;

procedure TFormPrincipal.ReportarProblemaClick(Sender: TObject);
begin
  LogarAcao('Abriu formulário "Reportar Problema"');
  MostrarReportarProblema(FSistemas);
end;

procedure TFormPrincipal.ConfigurarTema;
var
  Reg: TRegistry;
  EhEscuro: Boolean;
begin
  EhEscuro := False;
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', False) then
      try
        EhEscuro := Reg.ReadInteger('AppsUseLightTheme') = 0;
      except
      end;
  finally
    Reg.Free;
  end;

  if EhEscuro then
  begin
    Color := COR_FUNDO_ESCURO;
    PanelTopo.Color := $00333333;
    LabelTitulo.Font.Color := clWhite;
    LabelSub.Font.Color := clWhite;
    LabelBuild.Font.Color := clWhite;
    ScrollBox.Color := COR_FUNDO_ESCURO;
    FlowCards.Color := COR_FUNDO_ESCURO;
  end
  else
  begin
    Color := COR_FUNDO_PRINCIPAL;
    ScrollBox.Color := COR_FUNDO_PRINCIPAL;
    FlowCards.Color := COR_FUNDO_PRINCIPAL;
  end;

  // Estilo dos labels
  LabelTitulo.Font.Size := 24;
  LabelSub.Font.Size := 11;
  LabelBuild.Font.Size := 9;
end;

procedure TFormPrincipal.FiltroMudou(Sender: TObject);
begin
  AtualizarVisibilidadeCards;
end;

procedure TFormPrincipal.AtualizarVisibilidadeCards;
var
  Filtro: string;
  Item: TPair<string, TPanel>;
begin
  Filtro := LowerCase(Trim(FEdFiltro.Text));

  for Item in FMapaCards do
  begin
    if Filtro = '' then
      Item.Value.Visible := True
    else
      Item.Value.Visible := Pos(Filtro, LowerCase(Item.Key)) > 0;
  end;

  ScrollBox.VertScrollBar.Position := 0;
end;

procedure TFormPrincipal.KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // Ctrl+Q para sair
  if (Key = Ord('Q')) and (ssCtrl in Shift) then
  begin
    Application.Terminate;
  end
  // Ctrl+U para verificar atualizações agora
  else if (Key = Ord('U')) and (ssCtrl in Shift) then
  begin
    MessageDlg('Verificando atualizações...', mtInformation, [mbOK], 0);
    VerificarAtualizacoesAsync(AtualizacaoVerificada);
  end
  // Alt+R para reportar problema
  else if (Key = Ord('R')) and (ssAlt in Shift) then
  begin
    ReportarProblemaClick(nil);
  end;
end;

// Sobe a partir da pasta do executavel ate achar a raiz do projeto (onde fica o .dpr).
// Assim funciona tanto com o exe na raiz do projeto quanto rodando pela IDE.
// Os sistemas sao lidos de UMigradores.PastaSistemas: na pasta do projeto
// quando rodando pela IDE, e em %LOCALAPPDATA%\MultiMigrador\Sistemas quando
// distribuido -- assim a pasta do executavel fica limpa na maquina do cliente.
function TFormPrincipal.PastaBase: string;
begin
  Result := ExcludeTrailingPathDelimiter(PastaSistemas);
end;

// Procura o .exe do migrador dentro da pasta do sistema, escolhendo o build
// mais recente. As pastas sao projetos Delphi, entao olhamos apenas o nivel de
// topo das saidas de build em vez de varrer recursivamente -- uma varredura
// pegaria .exe de terceiros embutidos, como os do pgsql\bin.
// Se houver .dproj e algum .exe de mesmo nome, so esses entram na disputa.
function TFormPrincipal.LocalizarExecutavel(const ADir: string): string;
const
  SAIDAS: array[0..4] of string = ('', 'Win32\Release', 'Win64\Release',
                                   'Win32\Debug', 'Win64\Debug');
var
  Sub, Pasta, Arquivo, Alvo: string;
  Dprojs, Candidatos: TArray<string>;
  Data, Melhor: TDateTime;
begin
  Result := '';

  Alvo := '';
  Dprojs := TDirectory.GetFiles(ADir, '*.dproj', TSearchOption.soTopDirectoryOnly);
  if Length(Dprojs) > 0 then
    Alvo := TPath.GetFileNameWithoutExtension(Dprojs[0]) + '.exe';

  Candidatos := [];
  for Sub in SAIDAS do
  begin
    Pasta := TPath.Combine(ADir, Sub);
    if not TDirectory.Exists(Pasta) then
      Continue;
    for Arquivo in TDirectory.GetFiles(Pasta, '*.exe', TSearchOption.soTopDirectoryOnly) do
      if not SameText(ExtractFileName(Arquivo), 'unins000.exe') then
        Candidatos := Candidatos + [Arquivo];
  end;

  // O nome do projeto so filtra se de fato houver um exe correspondente; varios
  // migradores geram um exe com nome diferente do .dproj.
  if Alvo <> '' then
    for Arquivo in Candidatos do
      if SameText(ExtractFileName(Arquivo), Alvo) then
      begin
        Candidatos := [];
        for Sub in SAIDAS do
        begin
          Pasta := TPath.Combine(ADir, Sub);
          if TDirectory.Exists(Pasta) and TFile.Exists(TPath.Combine(Pasta, Alvo)) then
            Candidatos := Candidatos + [TPath.Combine(Pasta, Alvo)];
        end;
        Break;
      end;

  Melhor := 0;
  for Arquivo in Candidatos do
  begin
    Data := TFile.GetLastWriteTime(Arquivo);
    if (Result = '') or (Data > Melhor) then
    begin
      Result := Arquivo;
      Melhor := Data;
    end;
  end;
end;

procedure TFormPrincipal.CarregarSistemas;
var
  Dir, Nome, Base: string;
begin
  Base := PastaBase;
  FlowCards.DisableAlign;
  try
    for Dir in TDirectory.GetDirectories(Base, '*',
                 TSearchOption.soTopDirectoryOnly) do
    begin
      Nome := ExtractFileName(Dir);
      
      // Ignorar pastas de sistema/build do Delphi e controle de versao
      if SameText(Nome, 'Win32') or SameText(Nome, 'Win64') or
         SameText(Nome, '__history') or SameText(Nome, '__recovery') or
         SameText(Nome, '.git') or SameText(Nome, '.svn') or
         SameText(Nome, '.vs') then
        Continue;

      // O nome do card será o próprio nome da pasta
      FSistemas.Add(Nome);
      CriarCard(Nome, Dir);
    end;
  finally
    FlowCards.EnableAlign;
  end;

  if FlowCards.ControlCount = 0 then
    LabelSub.Caption := 'Nenhuma pasta de sistema encontrada em ' + Base;
end;

procedure TFormPrincipal.CriarCard(const ANome, ACaminho: string);
var
  Card: TPanel;
  Fundo, Sombra: TShape;
  LblNome, LblStatus, LblSubtitle: TLabel;
  ImgIcon: TImage;
  Exe, PngFile: string;
  PngFiles: TArray<string>;
  TemImagem: Boolean;
  TextLeft, TextWidth: Integer;
  BadgeStatus: TShape;
begin
  Exe := LocalizarExecutavel(ACaminho);

  // Procura por imagem .png na pasta do sistema
  PngFiles := TDirectory.GetFiles(ACaminho, '*.png', TSearchOption.soTopDirectoryOnly);
  TemImagem := Length(PngFiles) > 0;
  if TemImagem then
    PngFile := PngFiles[0]
  else
    PngFile := '';

  Card := TPanel.Create(Self);
  Card.Parent := FlowCards;
  Card.SetBounds(0, 0, 280, 160);  // Reduzido para layout mais compacto
  Card.BevelOuter := bvNone;
  Card.AlignWithMargins := True;
  Card.Margins.SetBounds(10, 10, 10, 10);  // Espaçamento adequado
  Card.ParentBackground := True;
  Card.ParentColor := True;
  Card.Cursor := crHandPoint;
  Card.Hint := ACaminho;
  Card.ShowHint := True;
  Card.Tag := FExes.Add(Exe);
  Card.OnClick := CardClick;
  Card.OnMouseEnter := CardMouseEnter;
  Card.OnMouseLeave := CardMouseLeave;
  FMapaCards.Add(ANome, Card);

  // Sombra com blur efeito
  Sombra := TShape.Create(Self);
  Sombra.Parent := Card;
  Sombra.SetBounds(4, 6, 272, 152);
  Sombra.Anchors := [akLeft, akTop, akRight, akBottom];
  Sombra.Shape := stRoundRect;
  Sombra.Brush.Color := COR_SOMBRA;
  Sombra.Pen.Style := psClear;
  Sombra.Enabled := False;

  // Fundo principal com borda mais refinada
  Fundo := TShape.Create(Self);
  Fundo.Parent := Card;
  Fundo.SetBounds(0, 0, 280, 160);
  Fundo.Anchors := [akLeft, akTop, akRight, akBottom];
  Fundo.Shape := stRoundRect;
  Fundo.Brush.Color := COR_CARD;
  Fundo.Pen.Style := psSolid;
  Fundo.Pen.Color := COR_BORDA;
  Fundo.Pen.Width := 1;
  Fundo.Enabled := False;

  // Ícone
  if TemImagem then
  begin
    ImgIcon := TImage.Create(Self);
    ImgIcon.Parent := Card;
    ImgIcon.SetBounds(12, 12, 80, 64);
    ImgIcon.Proportional := True;
    ImgIcon.Center := True;
    ImgIcon.Stretch := True;
    ImgIcon.Transparent := True;
    try
      ImgIcon.Picture.LoadFromFile(PngFile);
    except
      // Se houver erro ao carregar a imagem, ignora silenciosamente
    end;
    ImgIcon.OnClick := CardClick;
    ImgIcon.OnMouseEnter := CardMouseEnter;
    ImgIcon.OnMouseLeave := CardMouseLeave;

    TextLeft := 100;
    TextWidth := 170;
  end
  else
  begin
    TextLeft := 16;
    TextWidth := 252;
  end;

  // Nome do sistema em destaque
  LblNome := TLabel.Create(Self);
  LblNome.Parent := Card;
  LblNome.SetBounds(TextLeft, 12, TextWidth, 36);
  LblNome.AutoSize := False;
  LblNome.WordWrap := True;
  LblNome.Caption := ANome;
  LblNome.Font.Name := 'Segoe UI';
  LblNome.Font.Size := 12;
  LblNome.Font.Style := [fsBold];
  LblNome.Font.Color := $00333333;
  LblNome.Transparent := True;
  LblNome.OnClick := CardClick;
  LblNome.OnMouseEnter := CardMouseEnter;
  LblNome.OnMouseLeave := CardMouseLeave;

  // Subtítulo
  LblSubtitle := TLabel.Create(Self);
  LblSubtitle.Parent := Card;
  LblSubtitle.SetBounds(TextLeft, 48, TextWidth, 16);
  LblSubtitle.Caption := 'Migrador de Dados';
  LblSubtitle.Font.Name := 'Segoe UI';
  LblSubtitle.Font.Size := 8;
  LblSubtitle.Font.Color := $00999999;
  LblSubtitle.Transparent := True;
  LblSubtitle.OnClick := CardClick;
  LblSubtitle.OnMouseEnter := CardMouseEnter;
  LblSubtitle.OnMouseLeave := CardMouseLeave;

  // Status com mais destaque
  LblStatus := TLabel.Create(Self);
  LblStatus.Parent := Card;
  LblStatus.SetBounds(TextLeft, 66, TextWidth, 82);
  LblStatus.AutoSize := False;
  LblStatus.WordWrap := True;
  LblStatus.Font.Name := 'Segoe UI';
  LblStatus.Font.Size := 9;
  LblStatus.Transparent := True;
  LblStatus.OnClick := CardClick;
  LblStatus.OnMouseEnter := CardMouseEnter;
  LblStatus.OnMouseLeave := CardMouseLeave;

  // Badge de status
  BadgeStatus := TShape.Create(Self);
  BadgeStatus.Parent := Card;
  BadgeStatus.Shape := stCircle;
  BadgeStatus.Enabled := False;

  if Exe <> '' then
  begin
    LblStatus.Caption := ExtractRelativePath(IncludeTrailingPathDelimiter(ACaminho), Exe) +
      #13#10'Versão: ' + FormatDateTime('dd/mm/yyyy', TFile.GetLastWriteTime(Exe));
    LblStatus.Font.Color := clGrayText;
    BadgeStatus.Brush.Color := $0040C040;  // Verde
    BadgeStatus.SetBounds(TextLeft + TextWidth - 20, 16, 16, 16);
  end
  else
  begin
    LblStatus.Caption := '⚠️ Executável não encontrado';
    LblStatus.Font.Color := $004040FF;
    BadgeStatus.Brush.Color := $00FF4040;  // Vermelho
    BadgeStatus.SetBounds(TextLeft + TextWidth - 20, 16, 16, 16);
    Card.Cursor := crDefault;
  end;

  BadgeStatus.Pen.Style := psClear;
end;

// Os labels tambem disparam o clique, entao subimos ate o card.
procedure TFormPrincipal.CardClick(Sender: TObject);
var
  Card: TPanel;
  Exe: string;
begin
  if Sender is TControl then
  begin
    if Sender is TPanel then
      Card := TPanel(Sender)
    else
      Card := TPanel(TControl(Sender).Parent);
  end
  else
    Exit;

  Exe := FExes[Card.Tag];
  if Exe = '' then
  begin
    LogarErro('Executável não encontrado na pasta: ' + Card.Hint);
    MessageDlg('Nenhum executável (.exe) foi encontrado na pasta:'#13#10 + Card.Hint,
      mtWarning, [mbOK], 0);
    Exit;
  end;

  LogarAcao('Abriu: ' + ExtractFileName(Exe));
  if ShellExecute(Handle, 'open', PChar(Exe), nil,
       PChar(ExtractFilePath(Exe)), SW_SHOWNORMAL) <= 32 then
  begin
    LogarErro('Falha ao iniciar: ' + Exe);
    MessageDlg('Não foi possível iniciar:'#13#10 + Exe, mtError, [mbOK], 0);
  end;
end;

procedure TFormPrincipal.CardMouseEnter(Sender: TObject);
var
  i: Integer;
  Card: TPanel;
begin
  if Sender is TControl then
  begin
    if Sender is TPanel then
      Card := TPanel(Sender)
    else
      Card := TPanel(TControl(Sender).Parent);

    for i := 0 to Card.ControlCount - 1 do
    begin
      if (Card.Controls[i] is TShape) and (Card.Controls[i].Top = 0) then
      begin
        // Fundo
        TShape(Card.Controls[i]).Brush.Color := COR_HOVER;
        TShape(Card.Controls[i]).Pen.Color := COR_BORDA_HOVER;
        TShape(Card.Controls[i]).Pen.Width := 2;
      end
      else if Card.Controls[i] is TLabel then
      begin
        if TLabel(Card.Controls[i]).Font.Style = [fsBold] then
          TLabel(Card.Controls[i]).Font.Color := COR_BORDA_HOVER;
      end;
    end;
  end;
end;

procedure TFormPrincipal.CardMouseLeave(Sender: TObject);
var
  i: Integer;
  Card: TPanel;
begin
  if Sender is TControl then
  begin
    if Sender is TPanel then
      Card := TPanel(Sender)
    else
      Card := TPanel(TControl(Sender).Parent);

    for i := 0 to Card.ControlCount - 1 do
    begin
      if (Card.Controls[i] is TShape) and (Card.Controls[i].Top = 0) then
      begin
        // Fundo
        TShape(Card.Controls[i]).Brush.Color := COR_CARD;
        TShape(Card.Controls[i]).Pen.Color := COR_BORDA;
        TShape(Card.Controls[i]).Pen.Width := 1;
      end
      else if Card.Controls[i] is TLabel then
      begin
        if TLabel(Card.Controls[i]).Font.Style = [fsBold] then
          TLabel(Card.Controls[i]).Font.Color := $00333333;
      end;
    end;
  end;
end;

end.
