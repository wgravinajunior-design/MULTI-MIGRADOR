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
    procedure ImageLogoClick(Sender: TObject);
  private
    FExes: TStringList;
    FSistemas: TStringList;
    FBtReportar: TButton;
    FEdFiltro: TEdit;
    FLblNovoVersao: TLabel;
    FMapaCards: TDictionary<string, TPanel>;
    FEhTemaEscuro: Boolean;
    FVerificacaoManual: Boolean;
    function PastaBase: string;
    function LocalizarExecutavel(const ADir: string): string;
    function LocalizarImagemSistema(const ADir, ANomeSistema: string): string;
    procedure CarregarSistemas;
    procedure CriarCard(const ANome, ACaminho: string);
    procedure CardClick(Sender: TObject);
    procedure CardMouseEnter(Sender: TObject);
    procedure CardMouseLeave(Sender: TObject);
    procedure ReportarProblemaClick(Sender: TObject);
    procedure AtualizacaoVerificada(const AInfo: TInfoAtualizacao);
    procedure PosicionarAvisoVersao;
    procedure FiltroMudou(Sender: TObject);
    procedure AtualizarVisibilidadeCards;
    procedure ConfigurarTema;
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormResize(Sender: TObject);
  public
    destructor Destroy; override;
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

// Leitura segura de data/hora de arquivo, blindando contra exceções de I/O em arquivos bloqueados.
function ObterDataHoraModificacaoSegura(const ACaminho: string): TDateTime;
begin
  Result := 0;
  try
    if TFile.Exists(ACaminho) then
      Result := TFile.GetLastWriteTime(ACaminho);
  except
    Result := 0;
  end;
end;

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

  // Deixar título visível com cor branca
  LabelTitulo.Font.Color := clWhite;
  LabelSub.Font.Color := clWhite;
  LabelBuild.Font.Color := clWhite;

  // Campo de Filtro - lado direito da barra azul, alinhado a 15px do botão reportar
  FEdFiltro := TEdit.Create(Self);
  FEdFiltro.Parent := PanelTopo;
  FEdFiltro.SetBounds(PanelTopo.Width - 425, 50, 220, 28);
  FEdFiltro.Anchors := [akTop, akRight];
  FEdFiltro.Font.Size := 10;
  FEdFiltro.Font.Name := 'Segoe UI';
  FEdFiltro.TextHint := 'Buscar sistema...';
  FEdFiltro.OnChange := FiltroMudou;
  FEdFiltro.OnKeyDown := FormKeyDown;
  FEdFiltro.BorderStyle := bsSingle;

  // Aviso de nova versao: fica na linha de cima, logo antes da build. Antes
  // ficava na mesma linha do botao "Reportar Problema" e, como o TLabel usa
  // AutoSize, o texto crescia por cima do botao. A posicao exata e calculada
  // em PosicionarAvisoVersao, quando o texto ja existe.
  FLblNovoVersao := TLabel.Create(Self);
  FLblNovoVersao.Parent := PanelTopo;
  FLblNovoVersao.Anchors := [akTop, akRight];
  FLblNovoVersao.Transparent := True;
  // taRightJustify: com AutoSize o label cresce para a ESQUERDA, mantendo a
  // borda direita parada. E o que garante que ele nunca avance sobre o que
  // estiver a direita, por maior que fique o texto.
  FLblNovoVersao.Alignment := taRightJustify;
  FLblNovoVersao.Font.Style := [fsBold];
  FLblNovoVersao.Font.Color := $00FFD700;
  FLblNovoVersao.Font.Size := 9;
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
  KeyPreview := True;
  Self.OnKeyDown := FormKeyDown;
  Self.OnResize := FormResize;

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
  BuildDate := ObterDataHoraModificacaoSegura(ExePath);
  if BuildDate > 0 then
    LabelBuild.Caption := 'Build: ' + FormatDateTime('dd/mm/yyyy hh:nn', BuildDate)
  else
    LabelBuild.Caption := 'Build: --';

  // Mostra a versao atual do app ao lado da data de build.
  LabelBuild.Caption := 'v' + APP_VERSAO + '  |  ' + LabelBuild.Caption;

  CarregarSistemas;

  // Limpeza pos-atualizacao + exibe o changelog da versao recem-instalada.
  // Adiado: o changelog abre um dialogo modal e, chamado aqui dentro do
  // FormCreate, prendia o app numa janela em branco (form ainda nao pintado)
  // com o dialogo escondido atras dela.
  TThread.ForceQueue(nil,
    procedure
    begin
      ProcessarStartup;
    end);

  // Verifica no GitHub se ha versao mais nova (em background, sem travar a UI).
  VerificarAtualizacoesAsync(AtualizacaoVerificada);
end;

// Encosta o aviso de nova versao imediatamente antes da build, na mesma linha,
// com uma folga fixa. Como o texto da build tambem varia de tamanho (a data
// entra depois), a conta e feita aqui, a partir da posicao real do label.
procedure TFormPrincipal.PosicionarAvisoVersao;
const
  FOLGA = 28;  // espaco entre o aviso e a linha "vX.Y.Z | Build: ..."
begin
  if not FLblNovoVersao.Visible then
    Exit;

  FLblNovoVersao.Top := LabelBuild.Top +
    (LabelBuild.Height - FLblNovoVersao.Height) div 2;
  FLblNovoVersao.Left := LabelBuild.Left - FOLGA - FLblNovoVersao.Width;
end;

procedure TFormPrincipal.AtualizacaoVerificada(const AInfo: TInfoAtualizacao);
var
  Erro: string;
  Manual: Boolean;
begin
  if (Self = nil) or (csDestroying in ComponentState) or Application.Terminated then
    Exit;

  Manual := FVerificacaoManual;
  FVerificacaoManual := False;

  if not AInfo.Sucesso then
  begin
    LogarErro('Falha ao verificar atualizações: ' + AInfo.Erro);
    if Manual then
      MessageDlg('Não foi possível verificar atualizações no momento:'#13#10 + AInfo.Erro,
        mtWarning, [mbOK], 0);
    Exit;
  end;

  if not AInfo.TemAtualizacao then
  begin
    if Manual then
      MessageDlg('Você já está utilizando a versão mais recente do Multi Migrador (v' + APP_VERSAO + ').',
        mtInformation, [mbOK], 0);
    Exit;
  end;

  FLblNovoVersao.Caption := '🔔 Nova versão ' + AInfo.VersaoRemota + ' disponível!';
  FLblNovoVersao.Visible := True;
  PosicionarAvisoVersao;
  LogarAcao('Nova versão disponível: ' + AInfo.VersaoRemota);

  if not PerguntarAtualizar(AInfo) then
    Exit;

  if BaixarComProgresso(AInfo, Erro) then
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
  FreeAndNil(FExes);
  FreeAndNil(FSistemas);
  FreeAndNil(FMapaCards);
end;

destructor TFormPrincipal.Destroy;
begin
  FreeAndNil(FExes);
  FreeAndNil(FSistemas);
  FreeAndNil(FMapaCards);
  inherited;
end;

procedure TFormPrincipal.ImageLogoClick(Sender: TObject);
begin
  // Espaço reservado
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

  FEhTemaEscuro := EhEscuro;

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

function NormalizarTextoBusca(const S: string): string;
var
  C: Char;
begin
  Result := '';
  for C in Trim(S).ToLower do
  begin
    case Ord(C) of
      $00E1, $00E0, $00E2, $00E3, $00E4: Result := Result + 'a'; // á, à, â, ã, ä
      $00E9, $00EA, $00E8, $00EB:       Result := Result + 'e'; // é, ê, è, ë
      $00ED, $00EC, $00EE, $00EF:       Result := Result + 'i'; // í, ì, î, ï
      $00F3, $00F2, $00F4, $00F5, $00F6: Result := Result + 'o'; // ó, ò, ô, õ, ö
      $00FA, $00F9, $00FB, $00FC:       Result := Result + 'u'; // ú, ù, û, ü
      $00E7:                             Result := Result + 'c'; // ç
      $00F1:                             Result := Result + 'n'; // ñ
    else
      Result := Result + C;
    end;
  end;
end;

procedure TFormPrincipal.AtualizarVisibilidadeCards;
var
  Filtro: string;
  Item: TPair<string, TPanel>;
  TotalVisiveis: Integer;
  Visivel: Boolean;
begin
  Filtro := NormalizarTextoBusca(FEdFiltro.Text);
  TotalVisiveis := 0;

  for Item in FMapaCards do
  begin
    if Filtro = '' then
    begin
      Item.Value.Visible := True;
      Inc(TotalVisiveis);
    end
    else
    begin
      Visivel := Pos(Filtro, NormalizarTextoBusca(Item.Key)) > 0;
      Item.Value.Visible := Visivel;
      if Visivel then
        Inc(TotalVisiveis);
    end;
  end;

  ScrollBox.VertScrollBar.Position := 0;
  FlowCards.Realign;

  if (Filtro <> '') and (TotalVisiveis = 0) then
    LabelSub.Caption := 'Nenhum sistema encontrado para a busca "' + FEdFiltro.Text + '"'
  else
    LabelSub.Caption := 'Selecione o sistema de origem da migração';
end;

procedure TFormPrincipal.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // Ctrl+Q para sair
  if (Key = Ord('Q')) and (ssCtrl in Shift) then
  begin
    Application.Terminate;
  end
  // Ctrl+U para verificar atualizações agora
  else if (Key = Ord('U')) and (ssCtrl in Shift) then
  begin
    LogarAcao('Verificação manual de atualizações disparada pelo atalho Ctrl+U');
    FVerificacaoManual := True;
    VerificarAtualizacoesAsync(AtualizacaoVerificada, True);
  end
  // Alt+R para reportar problema
  else if (Key = Ord('R')) and (ssAlt in Shift) then
  begin
    ReportarProblemaClick(nil);
  end;
end;

procedure TFormPrincipal.FormResize(Sender: TObject);
begin
  PosicionarAvisoVersao;
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

function EhDesinstalador(const ANomeArq: string): Boolean;
var
  NomeLower: string;
begin
  NomeLower := LowerCase(ANomeArq);
  Result := NomeLower.StartsWith('unins') or
            NomeLower.StartsWith('uninstall') or
            (NomeLower = 'setup.exe') or
            (NomeLower = 'update.exe');
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
      if not EhDesinstalador(ExtractFileName(Arquivo)) then
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
    Data := ObterDataHoraModificacaoSegura(Arquivo);
    if (Result = '') or (Data > Melhor) then
    begin
      Result := Arquivo;
      Melhor := Data;
    end;
  end;
end;

// GetFileAttributes direto: nao levanta excecao se a pasta sumir ou estiver
// sem permissao entre a listagem e a checagem -- so devolve False.
function PastaOculta(const ADir: string): Boolean;
var
  Attr: DWORD;
begin
  Attr := GetFileAttributes(PChar(ADir));
  Result := (Attr <> INVALID_FILE_ATTRIBUTES) and
            ((Attr and FILE_ATTRIBUTE_HIDDEN) <> 0);
end;

function TFormPrincipal.LocalizarImagemSistema(const ADir, ANomeSistema: string): string;
var
  Arquivos, Candidatos: TArray<string>;
  Arq, Ext, NomeBase: string;
const
  EXTS_VALIDAS: array[0..4] of string = ('.png', '.jpg', '.jpeg', '.bmp', '.ico');
begin
  Result := '';
  Candidatos := [];
  for Ext in EXTS_VALIDAS do
  begin
    Arquivos := TDirectory.GetFiles(ADir, '*' + Ext, TSearchOption.soTopDirectoryOnly);
    Candidatos := Candidatos + Arquivos;
  end;

  if Length(Candidatos) = 0 then
    Exit;

  for Arq in Candidatos do
  begin
    NomeBase := LowerCase(TPath.GetFileNameWithoutExtension(Arq));
    if (NomeBase = 'logo') or (NomeBase = 'icon') or (NomeBase = 'icone') or
       (NomeBase = LowerCase(ANomeSistema)) then
      Exit(Arq);
  end;

  Result := Candidatos[0];
end;

procedure TFormPrincipal.CarregarSistemas;
var
  Dir, Nome, Base: string;
  Pastas: TArray<string>;
begin
  Base := PastaBase;
  FlowCards.DisableAlign;
  try
    Pastas := TDirectory.GetDirectories(Base, '*', TSearchOption.soTopDirectoryOnly);
    TArray.Sort<string>(Pastas);
    for Dir in Pastas do
    begin
      Nome := ExtractFileName(Dir);

      // Pasta oculta ou comecada por ponto (.git, .vs, .claude, ...) nunca e um
      // migrador. Regra geral em vez de lista de excecoes: cada ferramenta nova
      // cria a sua pasta e ela aparecia como card com "Executavel nao encontrado".
      if Nome.StartsWith('.') or PastaOculta(Dir) then
        Continue;

      // Saidas de build do Delphi e pasta de log
      if SameText(Nome, 'Win32') or SameText(Nome, 'Win64') or
         SameText(Nome, '__history') or SameText(Nome, '__recovery') or
         SameText(Nome, 'log') then
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
  Exe, ImgFile: string;
  TemImagem: Boolean;
  TextLeft, TextWidth: Integer;
  BadgeStatus: TShape;
  DtModif: TDateTime;
  DtTexto: string;
begin
  Exe := LocalizarExecutavel(ACaminho);

  // Procura por imagem (.png, .jpg, .jpeg, .bmp, .ico) com prioridade para logos/ícones
  ImgFile := LocalizarImagemSistema(ACaminho, ANome);
  TemImagem := (ImgFile <> '');

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
  if FEhTemaEscuro then
    Sombra.Brush.Color := COR_SOMBRA_ESCURO
  else
    Sombra.Brush.Color := COR_SOMBRA;
  Sombra.Pen.Style := psClear;
  Sombra.Enabled := False;

  // Fundo principal com borda mais refinada
  Fundo := TShape.Create(Self);
  Fundo.Parent := Card;
  Fundo.SetBounds(0, 0, 280, 160);
  Fundo.Anchors := [akLeft, akTop, akRight, akBottom];
  Fundo.Shape := stRoundRect;
  if FEhTemaEscuro then
  begin
    Fundo.Brush.Color := COR_CARD_ESCURO;
    Fundo.Pen.Color := COR_BORDA_ESCURO;
  end
  else
  begin
    Fundo.Brush.Color := COR_CARD;
    Fundo.Pen.Color := COR_BORDA;
  end;
  Fundo.Pen.Style := psSolid;
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
      ImgIcon.Picture.LoadFromFile(ImgFile);
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
  if FEhTemaEscuro then
    LblNome.Font.Color := $00E0E0E0
  else
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
  if FEhTemaEscuro then
    LblSubtitle.Font.Color := $00888888
  else
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
    DtModif := ObterDataHoraModificacaoSegura(Exe);
    if DtModif > 0 then
      DtTexto := FormatDateTime('dd/mm/yyyy', DtModif)
    else
      DtTexto := '--';

    LblStatus.Caption := ExtractRelativePath(IncludeTrailingPathDelimiter(ACaminho), Exe) +
      #13#10'Versão: ' + DtTexto;
    if FEhTemaEscuro then
      LblStatus.Font.Color := $00AAAAAA
    else
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
    else if (TControl(Sender).Parent is TPanel) then
      Card := TPanel(TControl(Sender).Parent)
    else
      Exit;
  end
  else
    Exit;

  if (Card = nil) or (Card.Tag < 0) or (Card.Tag >= FExes.Count) then
    Exit;

  Exe := FExes[Card.Tag];
  if Exe = '' then
  begin
    LogarErro('Executável não encontrado na pasta: ' + Card.Hint);
    MessageDlg('Nenhum executável (.exe) foi encontrado na pasta:'#13#10 + Card.Hint,
      mtWarning, [mbOK], 0);
    Exit;
  end;

  if not TFile.Exists(Exe) then
  begin
    LogarErro('Arquivo executável inexistente no disco: ' + Exe);
    MessageDlg('O executável do migrador não foi encontrado no disco:'#13#10 + Exe,
      mtError, [mbOK], 0);
    Exit;
  end;

  // As orientacoes deixaram de ser exibidas aqui: cada migrador passou a
  // apresentar as suas proprias, com os requisitos especificos do sistema.
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
        // Fundo do card
        if FEhTemaEscuro then
        begin
          TShape(Card.Controls[i]).Brush.Color := COR_HOVER_ESCURO;
          TShape(Card.Controls[i]).Pen.Color := COR_BORDA_HOVER_ESCURO;
        end
        else
        begin
          TShape(Card.Controls[i]).Brush.Color := COR_HOVER;
          TShape(Card.Controls[i]).Pen.Color := COR_BORDA_HOVER;
        end;
        TShape(Card.Controls[i]).Pen.Width := 2;
      end
      else if Card.Controls[i] is TLabel then
      begin
        if TLabel(Card.Controls[i]).Font.Style = [fsBold] then
        begin
          if FEhTemaEscuro then
            TLabel(Card.Controls[i]).Font.Color := COR_BORDA_HOVER_ESCURO
          else
            TLabel(Card.Controls[i]).Font.Color := COR_BORDA_HOVER;
        end;
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
        // Fundo do card restaurado
        if FEhTemaEscuro then
        begin
          TShape(Card.Controls[i]).Brush.Color := COR_CARD_ESCURO;
          TShape(Card.Controls[i]).Pen.Color := COR_BORDA_ESCURO;
        end
        else
        begin
          TShape(Card.Controls[i]).Brush.Color := COR_CARD;
          TShape(Card.Controls[i]).Pen.Color := COR_BORDA;
        end;
        TShape(Card.Controls[i]).Pen.Width := 1;
      end
      else if Card.Controls[i] is TLabel then
      begin
        if TLabel(Card.Controls[i]).Font.Style = [fsBold] then
        begin
          if FEhTemaEscuro then
            TLabel(Card.Controls[i]).Font.Color := $00E0E0E0
          else
            TLabel(Card.Controls[i]).Font.Color := $00333333;
        end;
      end;
    end;
  end;
end;

end.
