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
//  - Commitar os migradores novos/alterados e inclui-los na lista do
//    gerar_recursos.bat (o zip e montado com "git archive HEAD": o que nao
//    estiver commitado e listado NAO entra no pacote).
//  - Alterar APP_VERSAO abaixo (ex.: '1.0.1') e o VerInfo no .dproj.
//  - Rodar gerar_recursos.bat e recompilar.
//  - Criar um Release no GitHub com tag 'v1.0.1', anexar MultiMigrador.exe e
//    escrever nas notas o que mudou. O exe nao e versionado no repositorio
//    (ver .gitignore): o Release e a unica forma de distribui-lo.
//
// HTTP via THTTPClient (WinHTTP) -> HTTPS nativo, sem depender do OpenSSL.

interface

uses
  System.SysUtils, System.Classes;

const
  APP_VERSAO   = '1.1.35';                   // <-- bump a cada release
  GITHUB_OWNER = 'wgravinajunior-design';
  GITHUB_REPO  = 'MULTI-MIGRADOR';
  NOME_EXE     = 'MultiMigrador.exe';

type
  TInfoAtualizacao = record
    Sucesso: Boolean;         // a consulta ao GitHub funcionou
    TemAtualizacao: Boolean;  // ha versao maior disponivel
    VersaoRemota: string;
    UrlDownload: string;      // browser_download_url do .exe
    Notas: string;            // corpo do release
    Erro: string;
    SHA256: string;           // hash SHA256 para validacao
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
// Tira o 'v' da tag do GitHub ('v1.1.7' -> '1.1.7'), para exibir ao usuario.
function LimparVersao(const S: string): string;

function CompararVersoes(const A, B: string): Integer;

// Mostra progress bar enquanto baixa e instala. Bloqueia ate terminar.
function BaixarComProgresso(const AInfo: TInfoAtualizacao; out AErro: string): Boolean;

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
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.Graphics, Vcl.Dialogs, Vcl.ExtCtrls,
  Vcl.ComCtrls, System.Win.Registry, ULogger, System.Hash;

const
  ARQ_CHANGELOG = 'CHANGELOG_PENDENTE.txt';
  SUFIXO_OLD    = '.old';
  SUFIXO_UPDATE = '.update';
  CACHE_HOURS   = 24;

function DirApp: string;
begin
  Result := ExtractFilePath(ParamStr(0));
end;

function CaminhoExeAtual: string;
begin
  Result := ParamStr(0);
end;

{ ----- Cache de Versao ----- }

function ObterUltimoCheckCache(out AInfo: TInfoAtualizacao): Boolean;
var
  Reg: TRegistry;
  Timestamp, JsonData: string;
  DataHora, Agora: TDateTime;
begin
  Result := False;
  FillChar(AInfo, SizeOf(AInfo), 0);

  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKey('Software\MultiMigrador\Cache', False) then
      Exit;

    try
      Timestamp := Reg.ReadString('VersoesCheckTime');
      JsonData := Reg.ReadString('VersoesCheckData');
    except
      Exit;
    end;

    if (Timestamp = '') or (JsonData = '') then
      Exit;

    // Verifica se cache ainda � v�lido (< 24 horas)
    if not TryStrToDateTime(Timestamp, DataHora) then
      Exit;

    Agora := Now;
    if (Agora - DataHora) > (CACHE_HOURS / 24.0) then
      Exit;

    // Parse JSON do cache
    try
      AInfo.Sucesso := True;
      AInfo.VersaoRemota := Reg.ReadString('VersaoRemota');
      AInfo.UrlDownload := Reg.ReadString('UrlDownload');
      AInfo.Notas := Reg.ReadString('Notas');
      AInfo.TemAtualizacao := Reg.ReadBool('TemAtualizacao');
      Result := True;
      LogarAcao('Usando cache de vers�o (verif. h� ' +
        FormatDateTime('h:mm', Agora - DataHora) + ')');
    except
      Exit;
    end;
  finally
    Reg.Free;
  end;
end;

procedure SalvarCacheVersao(const AInfo: TInfoAtualizacao);
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('Software\MultiMigrador\Cache', True) then
    begin
      Reg.WriteString('VersoesCheckTime', DateTimeToStr(Now));
      Reg.WriteString('VersaoRemota', AInfo.VersaoRemota);
      Reg.WriteString('UrlDownload', AInfo.UrlDownload);
      Reg.WriteString('Notas', AInfo.Notas);
      Reg.WriteBool('TemAtualizacao', AInfo.TemAtualizacao);
    end;
  finally
    Reg.Free;
  end;
end;

// Apaga o cache de verificacao. Obrigatorio depois de atualizar: o cache guarda
// TemAtualizacao por CACHE_HOURS e, sem limpar, a versao recem-instalada leria
// esse "tem atualizacao" antigo e pediria para atualizar de novo, em loop.
procedure LimparCacheVersao;
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    try
      Reg.DeleteKey('Software\MultiMigrador\Cache');
    except
      // cache inexistente ou sem permissao: nao e motivo para falhar a atualizacao
    end;
  finally
    Reg.Free;
  end;
end;

{ ----- Validacao de Integridade ----- }

function CalcularSHA256Arquivo(const ACaminho: string): string;
var
  HashSHA2: THashSHA2;
  FS: TFileStream;
  Buffer: TBytes;
  BytesRead: Int64;
const
  BUFFER_SIZE = 1024 * 1024; // 1MB chunks
begin
  if not TFile.Exists(ACaminho) then
    Exit('');

  FS := TFileStream.Create(ACaminho, fmOpenRead);
  try
    SetLength(Buffer, BUFFER_SIZE);
    HashSHA2 := THashSHA2.Create;

    repeat
      BytesRead := FS.Read(Buffer[0], BUFFER_SIZE);
      if BytesRead > 0 then
      begin
        SetLength(Buffer, BytesRead);
        HashSHA2.Update(Buffer);
        SetLength(Buffer, BUFFER_SIZE);
      end;
    until BytesRead = 0;

    Result := HashSHA2.HashAsString;
  finally
    FS.Free;
  end;
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
  // Tenta usar cache primeiro
  if not ObterUltimoCheckCache(FInfo) then
  begin
    // Se cache inv�lido, consulta GitHub
    FInfo := ConsultarUltimoRelease;
    // Salva resultado no cache
    if FInfo.Sucesso then
      SalvarCacheVersao(FInfo);
  end;

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

// Janela mostrada durante o download. A barra e desenhada com dois paineis (um
// trilho e um bloco que corre dentro dele) em vez do TProgressBar em modo
// marquee: o marquee do Windows depende do tema da maquina e, sem tema, fica
// uma caixa cinza parada -- exatamente o que dava a impressao de travado.
type
  TJanelaProgresso = class
  private
    FForm: TForm;
    FTrilho, FBloco: TPanel;
    FTimer: TTimer;
    FPos: Integer;
    FOk: Boolean;
    FErro: string;
    procedure Animar(Sender: TObject);
    procedure Concluiu(Sender: TObject);
    procedure Montar(const AVersao: string);
  public
    function Executar(const AInfo: TInfoAtualizacao; out AErro: string): Boolean;
  end;

const
  LARGURA_BLOCO = 130;
  PASSO_BLOCO   = 7;

  COR_TRILHO = $00E6E6E6;  // cinza claro do fundo da barra
  COR_BLOCO  = $00D47800;  // azul (BGR) do bloco que corre
  COR_TITULO = $003F3F3F;

procedure TJanelaProgresso.Animar(Sender: TObject);
begin
  Inc(FPos, PASSO_BLOCO);
  if FPos > FTrilho.ClientWidth then
    FPos := -LARGURA_BLOCO;
  FBloco.Left := FPos;
end;

// Chamado na thread principal quando o download termina (OnTerminate roda
// sincronizado), entao pode mexer na janela com seguranca.
procedure TJanelaProgresso.Concluiu(Sender: TObject);
begin
  FTimer.Enabled := False;
  FForm.ModalResult := mrOk;
end;

procedure TJanelaProgresso.Montar(const AVersao: string);
var
  Lb: TLabel;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Caption := 'Atualizando o Multi Migrador';
  FForm.Position := poScreenCenter;
  FForm.BorderStyle := bsDialog;
  FForm.BorderIcons := [];   // sem X: fechar no meio do download deixaria o exe pela metade
  FForm.ClientWidth := 480;
  FForm.ClientHeight := 190;
  FForm.Color := clWhite;
  FForm.Font.Name := 'Segoe UI';
  FForm.Font.Height := -12;

  Lb := TLabel.Create(FForm);
  Lb.Parent := FForm;
  Lb.SetBounds(32, 30, 420, 24);
  Lb.AutoSize := False;
  Lb.Font.Size := 12;
  Lb.Font.Color := COR_TITULO;
  Lb.Caption := 'Baixando a versão ' + AVersao;

  Lb := TLabel.Create(FForm);
  Lb.Parent := FForm;
  Lb.SetBounds(32, 60, 420, 20);
  Lb.AutoSize := False;
  Lb.Font.Color := clGrayText;
  Lb.Caption := 'Não feche o programa.';

  FTrilho := TPanel.Create(FForm);
  FTrilho.Parent := FForm;
  FTrilho.SetBounds(32, 100, 416, 8);
  FTrilho.BevelOuter := bvNone;
  FTrilho.ParentBackground := False;
  FTrilho.Color := COR_TRILHO;

  FBloco := TPanel.Create(FForm);
  FBloco.Parent := FTrilho;
  FBloco.SetBounds(-LARGURA_BLOCO, 0, LARGURA_BLOCO, 8);
  FBloco.BevelOuter := bvNone;
  FBloco.ParentBackground := False;
  FBloco.Color := COR_BLOCO;

  Lb := TLabel.Create(FForm);
  Lb.Parent := FForm;
  Lb.SetBounds(32, 130, 416, 40);
  Lb.AutoSize := False;
  Lb.WordWrap := True;
  Lb.Font.Color := clGrayText;
  Lb.Caption := 'O download leva alguns segundos. Quando terminar, o programa ' +
                'reinicia sozinho na versão nova.';
end;

function TJanelaProgresso.Executar(const AInfo: TInfoAtualizacao;
  out AErro: string): Boolean;
var
  Info: TInfoAtualizacao;
  Thread: TThread;
begin
  Info := AInfo;          // copia local: e ela que a thread captura
  FOk := False;
  FErro := '';
  FPos := -LARGURA_BLOCO;

  Montar(LimparVersao(AInfo.VersaoRemota));
  try
    FTimer := TTimer.Create(FForm);
    FTimer.Interval := 15;
    FTimer.OnTimer := Animar;
    FTimer.Enabled := True;

    Thread := TThread.CreateAnonymousThread(
      procedure
      begin
        FOk := BaixarEInstalar(Info, FErro);
      end);
    Thread.FreeOnTerminate := True;
    Thread.OnTerminate := Concluiu;
    Thread.Start;

    FForm.ShowModal;   // so sai quando Concluiu fechar
  finally
    FForm.Free;
  end;

  AErro := FErro;
  Result := FOk;
end;

function BaixarComProgresso(const AInfo: TInfoAtualizacao; out AErro: string): Boolean;
var
  Janela: TJanelaProgresso;
begin
  Janela := TJanelaProgresso.Create;
  try
    Result := Janela.Executar(AInfo, AErro);
  finally
    Janela.Free;
  end;
end;

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
        LogarErro('Download falhou: HTTP ' + IntToStr(Resp.StatusCode));
        if TFile.Exists(ExeNovo) then TFile.Delete(ExeNovo);
        Exit;
      end;

      // Valida SHA256 se dispon�vel
      if AInfo.SHA256 <> '' then
      begin
        var SHA256Calculado := CalcularSHA256Arquivo(ExeNovo);
        if SHA256Calculado = '' then
        begin
          AErro := 'Nao foi possivel calcular SHA256 do arquivo.';
          LogarErro(AErro);
          if TFile.Exists(ExeNovo) then TFile.Delete(ExeNovo);
          Exit;
        end;

        if not SameText(SHA256Calculado, AInfo.SHA256) then
        begin
          AErro := 'Validacao SHA256 falhou. Arquivo pode estar corrompido.';
          LogarErro('SHA256 esperado: ' + AInfo.SHA256);
          LogarErro('SHA256 obtido: ' + SHA256Calculado);
          if TFile.Exists(ExeNovo) then TFile.Delete(ExeNovo);
          Exit;
        end;
        LogarAcao('SHA256 validado com sucesso');
      end;

    except
      on E: Exception do
      begin
        AErro := 'Erro ao baixar: ' + E.Message;
        LogarErro(AErro);
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
      LogarErro(AErro);
      // tenta reverter
      try
        if (not TFile.Exists(ExeAtual)) and TFile.Exists(ExeOld) then
          RenameFile(ExeOld, ExeAtual);
      except end;
      Exit;
    end;
  end;

  // Limpa o cache de atualizacao SEMPRE que conseguir fazer o swap,
  // mesmo que o changelog falhe depois. Se falhar antes (ex: download,
  // validacao SHA256), o cache fica intacto e o user pode tentar de novo.
  try
    LimparCacheVersao;
  except end;

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
  Dir, ArqOld, ArqChange: string;
begin
  Dir := DirApp;

  // Remove o exe antigo deixado pela atualizacao anterior (best effort).
  ArqOld := CaminhoExeAtual + SUFIXO_OLD;
  if TFile.Exists(ArqOld) then
    try TFile.Delete(ArqOld); except end;

  // Remove o changelog pendente (nao mostra mais tela de novidades).
  ArqChange := TPath.Combine(Dir, ARQ_CHANGELOG);
  if TFile.Exists(ArqChange) then
    try TFile.Delete(ArqChange); except end;
end;

{ ----- Dialogo de confirmacao ----- }

// As notas do release chegam em Markdown e com quebra de linha variavel: o
// GitHub devolve so #10 quando o texto foi enviado assim. O Memo do Windows so
// quebra linha em #13#10, entao sem normalizar sai tudo grudado numa linha so.
// Alem disso tiramos a marcacao (##, **, crases), que num Memo simples apareceria
// como lixo, e deixamos um item por linha.
function FormatarNotas(const ANotas: string): string;
var
  Origem: TArray<string>;
  Saida: TStringBuilder;
  Linha: string;
  i: Integer;
  UltimaVazia: Boolean;
begin
  Origem := StringReplace(
              StringReplace(ANotas, #13#10, #10, [rfReplaceAll]),
              #13, #10, [rfReplaceAll]).Split([#10]);

  Saida := TStringBuilder.Create;
  try
    UltimaVazia := True;  // evita comecar o texto com linha em branco
    for i := 0 to High(Origem) do
    begin
      Linha := Trim(Origem[i]);

      // negrito/italico e code span nao existem no Memo: viram texto puro
      Linha := StringReplace(Linha, '**', '', [rfReplaceAll]);
      Linha := StringReplace(Linha, '`', '', [rfReplaceAll]);

      // titulo "## Novidades" -> "Novidades"
      while Linha.StartsWith('#') do
        Linha := TrimLeft(Linha.Substring(1));

      // item "- texto" / "* texto" -> marcador com recuo, um por linha
      if Linha.StartsWith('- ') or Linha.StartsWith('* ') then
        Linha := '  ' + Chr($2022) + ' ' + TrimLeft(Linha.Substring(2));

      if Linha = '' then
      begin
        if UltimaVazia then Continue;  // nao acumula linhas em branco seguidas
        UltimaVazia := True;
      end
      else
        UltimaVazia := False;

      Saida.Append(Linha).Append(sLineBreak);
    end;
    Result := TrimRight(Saida.ToString);
  finally
    Saida.Free;
  end;
end;

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
      M.Text := 'O que mudou:' + sLineBreak + sLineBreak +
                FormatarNotas(AInfo.Notas)
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
