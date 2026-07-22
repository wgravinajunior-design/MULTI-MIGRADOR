unit UPrincipal;

interface

uses
  Winapi.Windows, Winapi.ShellAPI, System.SysUtils, System.Classes, System.IOUtils,
  System.UITypes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Imaging.pngimage, Vcl.Imaging.jpeg,
  UReportarProblema, UAtualizador;

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
    FExes: TStringList; // caminho do exe de cada card, indexado por Card.Tag
    FSistemas: TStringList; // nomes dos sistemas, para o dialogo de reporte
    FBtReportar: TButton;
    function PastaBase: string;
    function LocalizarExecutavel(const ADir: string): string;
    procedure CarregarSistemas;
    procedure CriarCard(const ANome, ACaminho: string);
    procedure CardClick(Sender: TObject);
    procedure CardMouseEnter(Sender: TObject);
    procedure CardMouseLeave(Sender: TObject);
    procedure ReportarProblemaClick(Sender: TObject);
    procedure AtualizacaoVerificada(const AInfo: TInfoAtualizacao);
  end;

var
  FormPrincipal: TFormPrincipal;

implementation

{$R *.dfm}

const
  COR_CARD        = clWhite;
  COR_HOVER       = $00FAFAFA; // Cinza muito claro
  COR_BORDA       = $00DFDFDF; // Cinza claro
  COR_BORDA_HOVER = 5052682;   // Azul escuro do topo
  COR_SOMBRA      = $00E6E6E6; // Cor da sombra

procedure TFormPrincipal.FormCreate(Sender: TObject);
var
  ExePath: string;
  BuildDate: TDateTime;
  W, H: Integer;
begin
  FExes := TStringList.Create;
  FSistemas := TStringList.Create;

  // Botao "Reportar Problema" no canto direito do cabecalho, ancorado a direita.
  FBtReportar := TButton.Create(Self);
  FBtReportar.Parent := PanelTopo;
  FBtReportar.SetBounds(PanelTopo.Width - 190, 46, 170, 30);
  FBtReportar.Anchors := [akTop, akRight];
  FBtReportar.Caption := 'REPORTAR PROBLEMA';
  FBtReportar.Font.Style := [fsBold];
  FBtReportar.OnClick := ReportarProblemaClick;

  // Ajusta a janela para meia tela e centraliza no monitor, garantindo dimensao minima confortavel
  W := Screen.WorkAreaWidth div 2;
  H := Screen.WorkAreaHeight div 2;
  if W < 900 then W := 900;
  if H < 620 then H := 620;

  Width := W;
  Height := H;
  Left := (Screen.WorkAreaWidth - Width) div 2;
  Top := (Screen.WorkAreaHeight - Height) div 2;

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
    Exit; // falha de rede/GitHub: silencioso, nao incomoda o usuario
  if not AInfo.TemAtualizacao then
    Exit;

  if not PerguntarAtualizar(AInfo) then
    Exit; // usuario escolheu "Nao"

  if BaixarEInstalar(AInfo, Erro) then
  begin
    MessageDlg('Atualizacao baixada. O sistema sera reiniciado na nova versao.',
      mtInformation, [mbOK], 0);
    ReiniciarApp;      // abre o novo exe
    Application.Terminate; // fecha o atual
  end
  else
    MessageDlg('Nao foi possivel atualizar:'#13#10 + Erro, mtError, [mbOK], 0);
end;

procedure TFormPrincipal.FormDestroy(Sender: TObject);
begin
  FExes.Free;
  FSistemas.Free;
end;

procedure TFormPrincipal.ReportarProblemaClick(Sender: TObject);
begin
  MostrarReportarProblema(FSistemas);
end;

// Sobe a partir da pasta do executavel ate achar a raiz do projeto (onde fica o .dpr).
// Assim funciona tanto com o exe na raiz do projeto quanto rodando pela IDE.
function TFormPrincipal.PastaBase: string;
var
  Dir, Pai: string;
begin
  Dir := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  repeat
    if TFile.Exists(TPath.Combine(Dir, 'MultiMigrador.dpr')) or
       TFile.Exists(TPath.Combine(Dir, 'MultiMigrador.dproj')) then
      Exit(Dir);
      
    Pai := ExtractFileDir(Dir);
    if Pai = Dir then // chegou na raiz do drive
      Break;
    Dir := Pai;
  until False;

  Result := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
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
  LblNome, LblStatus: TLabel;
  ImgIcon: TImage;
  Exe, PngFile: string;
  PngFiles: TArray<string>;
  TemImagem: Boolean;
  TextLeft, TextWidth: Integer;
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
  Card.SetBounds(0, 0, 280, 140);
  Card.BevelOuter := bvNone;
  Card.AlignWithMargins := True;
  Card.Margins.SetBounds(0, 0, 20, 20);
  Card.ParentBackground := True;
  Card.ParentColor := True;
  Card.Cursor := crHandPoint;
  Card.Hint := ACaminho;
  Card.ShowHint := True;
  Card.Tag := FExes.Add(Exe);
  Card.OnClick := CardClick;
  Card.OnMouseEnter := CardMouseEnter;
  Card.OnMouseLeave := CardMouseLeave;

  Sombra := TShape.Create(Self);
  Sombra.Parent := Card;
  Sombra.SetBounds(3, 4, 275, 134);
  Sombra.Anchors := [akLeft, akTop, akRight, akBottom];
  Sombra.Shape := stRoundRect;
  Sombra.Brush.Color := COR_SOMBRA;
  Sombra.Pen.Style := psClear;
  Sombra.Enabled := False;

  Fundo := TShape.Create(Self);
  Fundo.Parent := Card;
  Fundo.SetBounds(0, 0, 275, 134);
  Fundo.Anchors := [akLeft, akTop, akRight, akBottom];
  Fundo.Shape := stRoundRect;
  Fundo.Brush.Color := COR_CARD;
  Fundo.Pen.Style := psSolid;
  Fundo.Pen.Color := COR_BORDA;
  Fundo.Pen.Width := 1;
  Fundo.Enabled := False;

  if TemImagem then
  begin
    ImgIcon := TImage.Create(Self);
    ImgIcon.Parent := Card;
    ImgIcon.SetBounds(16, 16, 68, 52);
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

    TextLeft := 92;
    TextWidth := 168;
  end
  else
  begin
    TextLeft := 20;
    TextWidth := 240;
  end;

  LblNome := TLabel.Create(Self);
  LblNome.Parent := Card;
  LblNome.SetBounds(TextLeft, 14, TextWidth, 44);
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

  LblStatus := TLabel.Create(Self);
  LblStatus.Parent := Card;
  LblStatus.SetBounds(TextLeft, 60, TextWidth, 64);
  LblStatus.AutoSize := False;
  LblStatus.WordWrap := True;
  LblStatus.Font.Name := 'Segoe UI';
  LblStatus.Font.Size := 9;
  LblStatus.Transparent := True;
  LblStatus.OnClick := CardClick;
  LblStatus.OnMouseEnter := CardMouseEnter;
  LblStatus.OnMouseLeave := CardMouseLeave;
  
  if Exe <> '' then
  begin
    LblStatus.Caption := ExtractRelativePath(IncludeTrailingPathDelimiter(ACaminho), Exe) +
      #13#10'(' + FormatDateTime('dd/mm/yyyy hh:nn', TFile.GetLastWriteTime(Exe)) + ')';
    LblStatus.Font.Color := clGrayText;
  end
  else
  begin
    LblStatus.Caption := 'Executável não encontrado';
    LblStatus.Font.Color := $004040FF;
    Card.Cursor := crDefault;
  end;
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
    MessageDlg('Nenhum executavel (.exe) foi encontrado na pasta:'#13#10 + Card.Hint,
      mtWarning, [mbOK], 0);
    Exit;
  end;

  if ShellExecute(Handle, 'open', PChar(Exe), nil,
       PChar(ExtractFilePath(Exe)), SW_SHOWNORMAL) <= 32 then
    MessageDlg('Nao foi possivel iniciar:'#13#10 + Exe, mtError, [mbOK], 0);
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
