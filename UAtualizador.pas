unit UAtualizador;

// Auto-atualizacao via GitHub Releases.
//
// Fluxo:
//  1. Ao abrir, uma thread consulta releases/latest do repositorio e compara a
//     tag (ex.: v1.0.1) com APP_VERSAO.
//  2. Se houver versao maior, o app pergunta se deseja atualizar (Sim/Nao),
//     exibindo as notas do release.
//  3. Se Sim: baixa o .exe do release, renomeia o exe atual para .old, coloca o
//     novo no lugar, grava as notas em CHANGELOG_PENDENTE.txt, reinicia e fecha.
//  4. Ao reabrir na versao nova, o changelog pendente e mostrado uma vez.
//
// Publicar uma nova versao (passo manual do desenvolvedor):
//  - Alterar APP_VERSAO abaixo (ex.: '1.0.1'), recompilar.
//  - Criar um Release no GitHub com tag 'v1.0.1', anexar MultiMigrador.exe e
//    escrever nas notas o que mudou.
//
// HTTP via THTTPClient (WinHTTP) -> HTTPS nativo, sem depender do OpenSSL.

interface

uses
  System.SysUtils, System.Classes;

const
  APP_VERSAO   = '1.0.0';                    // <-- bump a cada release
  GITHUB_OWNER = 'wgravinajunior-design';
  GITHUB_REPO  = 'multi-migrador';
  NOME_EXE     = 'MultiMigrador.exe';

type
  TInfoAtualizacao = record
    Sucesso: Boolean;         // a consulta ao GitHub funcionou
    TemAtualizacao: Boolean;  // ha versao maior disponivel
    VersaoRemota: string;
    UrlDownload: string;      // browser_download_url do .exe
    Notas: string;            // corpo do release
    Erro: string;
  end;

  TResultadoProc = reference to procedure(const AInfo: TInfoAtualizacao);

  // Verifica atualizacoes em thread; chama AoTerminar (na thread principal) com o resultado.
  TAtualizadorThread = class(TThread)
  private
    FInfo: TInfoAtualizacao;
    FCallback: TResultadoProc;
    procedure DispararCallback;
  protected
    procedure Execute; override;
  public
    constructor Create(ACallback: TResultadoProc);
    property Info: TInfoAtualizacao read FInfo;
  end;

// Dispara a verificacao em background.
procedure VerificarAtualizacoesAsync(ACallback: TResultadoProc);

// Compara "1.2.3" x "1.2.10". Retorna <0, 0 ou >0. Aceita prefixo 'v'.
function CompararVersoes(const A, B: string): Integer;

// Baixa o novo exe e o instala no lugar do atual. Nao reinicia (o chamador faz).
function BaixarEInstalar(const AInfo: TInfoAtualizacao; out AErro: string): Boolean;

// Chamado no startup: remove o .old antigo e mostra o changelog pendente (uma vez).
procedure ProcessarStartup;

// Reinicia o app (novo exe) e sinaliza para o chamador encerrar.
procedure ReiniciarApp;

// Dialogo Sim/Nao com as notas do release. True = atualizar agora.
function PerguntarAtualizar(const AInfo: TInfoAtualizacao): Boolean;

implementation

uses
  Winapi.Windows, Winapi.ShellAPI, System.IOUtils, System.Generics.Collections,
  System.Net.HttpClient,
  System.Net.URLClient, System.JSON, System.UITypes,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.Graphics, Vcl.Dialogs, Vcl.ExtCtrls;

const
  ARQ_CHANGELOG = 'CHANGELOG_PENDENTE.txt';
  SUFIXO_OLD    = '.old';
  SUFIXO_UPDATE = '.update';

function DirApp: string;
begin
  Result := ExtractFilePath(ParamStr(0));
end;

function CaminhoExeAtual: string;
begin
  Result := ParamStr(0);
end;

{ ----- Comparacao de versoes ----- }

function LimparVersao(const S: string): string;
begin
  Result := Trim(S);
  if (Result <> '') and (CharInSet(Result[1], ['v', 'V'])) then
    Delete(Result, 1, 1);
end;

function CompararVersoes(const A, B: string): Integer;
var
  PA, PB: TArray<string>;
  i, NA, NB, Max: Integer;
  function ParteInt(const Arr: TArray<string>; Idx: Integer): Integer;
  begin
    if (Idx < Length(Arr)) then
    begin
      if not TryStrToInt(Trim(Arr[Idx]), Result) then
        Result := 0;
    end
    else
      Result := 0;
  end;
begin
  PA := LimparVersao(A).Split(['.']);
  PB := LimparVersao(B).Split(['.']);
  Max := Length(PA);
  if Length(PB) > Max then Max := Length(PB);

  for i := 0 to Max - 1 do
  begin
    NA := ParteInt(PA, i);
    NB := ParteInt(PB, i);
    if NA <> NB then
      Exit(NA - NB);
  end;
  Result := 0;
end;

{ ----- Consulta ao GitHub ----- }

function ConsultarUltimoRelease: TInfoAtualizacao;
var
  Cli: THTTPClient;
  Resp: IHTTPResponse;
  Url, Corpo: string;
  Raiz: TJSONObject;
  Assets: TJSONArray;
  Asset: TJSONValue;
  Nome, DlUrl, Tag: string;
  i: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result := Default(TInfoAtualizacao);

  Cli := THTTPClient.Create;
  try
    Cli.UserAgent := 'MultiMigrador-Updater';
    Cli.CustomHeaders['Accept'] := 'application/vnd.github+json';
    Cli.ConnectionTimeout := 15000;
    Cli.ResponseTimeout := 20000;
    Cli.HandleRedirects := True;

    Url := Format('https://api.github.com/repos/%s/%s/releases/latest',
      [GITHUB_OWNER, GITHUB_REPO]);
    try
      Resp := Cli.Get(Url);
    except
      on E: Exception do
      begin
        Result.Erro := 'Falha de conexao: ' + E.Message;
        Exit;
      end;
    end;

    // 404 = ainda nao ha releases publicados -> nao e erro, so nao ha update.
    if Resp.StatusCode = 404 then
    begin
      Result.Sucesso := True;
      Result.TemAtualizacao := False;
      Exit;
    end;

    if Resp.StatusCode <> 200 then
    begin
      Result.Erro := Format('GitHub retornou HTTP %d', [Resp.StatusCode]);
      Exit;
    end;

    Corpo := Resp.ContentAsString(TEncoding.UTF8);
    Raiz := TJSONObject.ParseJSONValue(Corpo) as TJSONObject;
    if Raiz = nil then
    begin
      Result.Erro := 'Resposta invalida do GitHub';
      Exit;
    end;
    try
      Tag := '';
      Raiz.TryGetValue<string>('tag_name', Tag);
      Result.VersaoRemota := Tag;
      Raiz.TryGetValue<string>('body', Result.Notas);

      // Procura um asset .exe (de preferencia MultiMigrador.exe).
      DlUrl := '';
      if Raiz.TryGetValue<TJSONArray>('assets', Assets) then
        for i := 0 to Assets.Count - 1 do
        begin
          Asset := Assets.Items[i];
          if not (Asset is TJSONObject) then Continue;
          Nome := '';
          (Asset as TJSONObject).TryGetValue<string>('name', Nome);
          if SameText(ExtractFileExt(Nome), '.exe') then
          begin
            (Asset as TJSONObject).TryGetValue<string>('browser_download_url', DlUrl);
            if SameText(Nome, NOME_EXE) then
              Break; // preferencia exata; senao fica com o ultimo .exe achado
          end;
        end;
      Result.UrlDownload := DlUrl;

      Result.Sucesso := True;
      Result.TemAtualizacao :=
        (Tag <> '') and (CompararVersoes(Tag, APP_VERSAO) > 0) and (DlUrl <> '');
    finally
      Raiz.Free;
    end;
  finally
    Cli.Free;
  end;
end;

{ ----- Thread ----- }

constructor TAtualizadorThread.Create(ACallback: TResultadoProc);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FCallback := ACallback;
end;

procedure TAtualizadorThread.Execute;
begin
  FInfo := ConsultarUltimoRelease;
  if Assigned(FCallback) then
    Synchronize(DispararCallback);
end;

procedure TAtualizadorThread.DispararCallback;
begin
  FCallback(FInfo);
end;

procedure VerificarAtualizacoesAsync(ACallback: TResultadoProc);
begin
  TAtualizadorThread.Create(ACallback).Start;
end;

{ ----- Download e instalacao ----- }

function BaixarEInstalar(const AInfo: TInfoAtualizacao; out AErro: string): Boolean;
var
  Cli: THTTPClient;
  Resp: IHTTPResponse;
  ExeAtual, ExeNovo, ExeOld, Dir: string;
  FS: TFileStream;
begin
  Result := False;
  AErro := '';
  Dir := DirApp;
  ExeAtual := CaminhoExeAtual;
  ExeNovo := ExeAtual + SUFIXO_UPDATE; // MultiMigrador.exe.update
  ExeOld := ExeAtual + SUFIXO_OLD;     // MultiMigrador.exe.old

  // 1) Baixa o novo exe para um arquivo temporario ao lado do atual.
  Cli := THTTPClient.Create;
  try
    Cli.UserAgent := 'MultiMigrador-Updater';
    Cli.HandleRedirects := True;
    Cli.ConnectionTimeout := 20000;
    Cli.ResponseTimeout := 120000;
    try
      if TFile.Exists(ExeNovo) then
        TFile.Delete(ExeNovo);
      FS := TFileStream.Create(ExeNovo, fmCreate);
      try
        Resp := Cli.Get(AInfo.UrlDownload, FS);
      finally
        FS.Free;
      end;
      if Resp.StatusCode <> 200 then
      begin
        AErro := Format('Download falhou (HTTP %d).', [Resp.StatusCode]);
        if TFile.Exists(ExeNovo) then TFile.Delete(ExeNovo);
        Exit;
      end;
    except
      on E: Exception do
      begin
        AErro := 'Erro ao baixar: ' + E.Message;
        if TFile.Exists(ExeNovo) then
          try TFile.Delete(ExeNovo); except end;
        Exit;
      end;
    end;
  finally
    Cli.Free;
  end;

  // 2) Troca os executaveis. O Windows permite renomear um exe em execucao.
  try
    if TFile.Exists(ExeOld) then
      TFile.Delete(ExeOld);
    RenameFile(ExeAtual, ExeOld);           // libera o nome
    RenameFile(ExeNovo, ExeAtual);          // novo assume o nome oficial
  except
    on E: Exception do
    begin
      AErro := 'Nao foi possivel substituir o executavel: ' + E.Message;
      // tenta reverter
      if (not TFile.Exists(ExeAtual)) and TFile.Exists(ExeOld) then
        RenameFile(ExeOld, ExeAtual);
      Exit;
    end;
  end;

  // 3) Grava o changelog para exibir no proximo start.
  try
    TFile.WriteAllText(TPath.Combine(Dir, ARQ_CHANGELOG),
      'Versao ' + LimparVersao(AInfo.VersaoRemota) + sLineBreak +
      StringOfChar('-', 40) + sLineBreak +
      AInfo.Notas, TEncoding.UTF8);
  except
    // changelog e opcional; ignora falha
  end;

  Result := True;
end;

procedure ReiniciarApp;
begin
  ShellExecute(0, 'open', PChar(CaminhoExeAtual), nil,
    PChar(DirApp), SW_SHOWNORMAL);
end;

{ ----- Startup: limpeza + changelog ----- }

procedure MostrarTexto(const ATitulo, ATexto: string);
var
  F: TForm;
  M: TMemo;
  B: TButton;
begin
  F := TForm.CreateNew(nil);
  try
    F.Caption := ATitulo;
    F.Position := poScreenCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 560;
    F.ClientHeight := 420;
    F.Font.Name := 'Segoe UI';
    F.Font.Height := -12;

    M := TMemo.Create(F);
    M.Parent := F;
    M.SetBounds(16, 16, 528, 350);
    M.ReadOnly := True;
    M.ScrollBars := ssVertical;
    M.WordWrap := True;
    M.Color := clWhite;
    M.Text := ATexto;

    B := TButton.Create(F);
    B.Parent := F;
    B.SetBounds(454, 378, 90, 30);
    B.Caption := 'OK';
    B.Default := True;
    B.ModalResult := mrOk;

    F.ShowModal;
  finally
    F.Free;
  end;
end;

procedure ProcessarStartup;
var
  Dir, ArqOld, ArqChange, Texto: string;
begin
  Dir := DirApp;

  // Remove o exe antigo deixado pela atualizacao anterior (best effort).
  ArqOld := CaminhoExeAtual + SUFIXO_OLD;
  if TFile.Exists(ArqOld) then
    try TFile.Delete(ArqOld); except end;

  // Mostra o changelog pendente uma unica vez.
  ArqChange := TPath.Combine(Dir, ARQ_CHANGELOG);
  if TFile.Exists(ArqChange) then
  begin
    try
      Texto := TFile.ReadAllText(ArqChange, TEncoding.UTF8);
    except
      Texto := '';
    end;
    try TFile.Delete(ArqChange); except end;
    if Trim(Texto) <> '' then
      MostrarTexto('Novidades desta versao', Texto);
  end;
end;

{ ----- Dialogo de confirmacao ----- }

function PerguntarAtualizar(const AInfo: TInfoAtualizacao): Boolean;
var
  F: TForm;
  L: TLabel;
  M: TMemo;
  BSim, BNao: TButton;
begin
  F := TForm.CreateNew(nil);
  try
    F.Caption := 'Atualizacao disponivel';
    F.Position := poScreenCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 560;
    F.ClientHeight := 400;
    F.Font.Name := 'Segoe UI';
    F.Font.Height := -12;

    L := TLabel.Create(F);
    L.Parent := F;
    L.SetBounds(16, 16, 528, 40);
    L.AutoSize := False;
    L.WordWrap := True;
    L.Font.Style := [fsBold];
    L.Caption := Format('Ha a versao %s disponivel (voce esta na %s).' + sLineBreak +
      'Deseja atualizar agora?',
      [LimparVersao(AInfo.VersaoRemota), APP_VERSAO]);

    M := TMemo.Create(F);
    M.Parent := F;
    M.SetBounds(16, 64, 528, 270);
    M.ReadOnly := True;
    M.ScrollBars := ssVertical;
    M.WordWrap := True;
    M.Color := clWhite;
    if Trim(AInfo.Notas) <> '' then
      M.Text := 'O que mudou:' + sLineBreak + AInfo.Notas
    else
      M.Text := '(sem notas de versao)';

    BSim := TButton.Create(F);
    BSim.Parent := F;
    BSim.SetBounds(346, 348, 100, 34);
    BSim.Caption := 'Sim, atualizar';
    BSim.Default := True;
    BSim.ModalResult := mrYes;

    BNao := TButton.Create(F);
    BNao.Parent := F;
    BNao.SetBounds(454, 348, 90, 34);
    BNao.Caption := 'Nao';
    BNao.Cancel := True;
    BNao.ModalResult := mrNo;

    Result := F.ShowModal = mrYes;
  finally
    F.Free;
  end;
end;

end.
