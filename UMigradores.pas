unit UMigradores;

// Extrai o pacote de migradores (recurso MIGRADORES = migradores.zip) para a
// pasta do executavel, tornando o Multi Migrador um unico exe que ja traz todos
// os sistemas embutidos. Assim, ao rodar em outra maquina, os cards aparecem
// mesmo sem as pastas soltas.
//
// Estrategia: um arquivo-marcador ".migradores.ver" guarda a versao ja extraida.
// Se o marcador nao existe ou aponta versao diferente, o zip e re-extraido
// (garantindo integridade a cada nova versao). A extracao e tolerante a arquivos
// em uso (um migrador aberto nao impede a abertura do launcher).

interface

// Pasta onde os migradores ficam (e de onde o launcher os lista).
//
//  - Rodando do projeto (existe MultiMigrador.dpr/.dproj ao lado do exe):
//    usa a propria pasta do projeto, para o desenvolvedor continuar mexendo
//    direto nas pastas versionadas.
//  - Distribuido (so o exe): usa %LOCALAPPDATA%\MultiMigrador\Sistemas.
//    Assim a pasta onde o usuario colocou o exe NAO e poluida com os 15
//    sistemas -- fica so o executavel, como pedido.
function PastaSistemas: string;

procedure ExtrairMigradores;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, System.Zip,
  UAtualizador, ULogger;

{$WARN SYMBOL_PLATFORM OFF}

const
  MARCADOR = '.migradores.ver';
  MIN_ESPACO_LIVRE_BYTES = 250 * 1024 * 1024; // 250 MB mínimos necessários

function TemEspacoLivreSuficiente(const ADir: string; ABytesNecessarios: UInt64): Boolean;
var
  LivreParaChamador, TotalBytes: Int64;
begin
  Result := True;
  if GetDiskFreeSpaceEx(PChar(ADir), LivreParaChamador, TotalBytes, nil) then
    Result := (UInt64(LivreParaChamador) >= ABytesNecessarios);
end;

function EhAmbienteDeProjeto: Boolean;
var
  Dir: string;
begin
  Dir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  Result := TFile.Exists(Dir + 'MultiMigrador.dpr') or
            TFile.Exists(Dir + 'MultiMigrador.dproj');
end;

function PastaSistemas: string;
var
  Base: string;
begin
  if EhAmbienteDeProjeto then
    Exit(IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))));

  // LOCALAPPDATA e nao TPath.GetHomePath: este ultimo devolve o Roaming, que
  // em rede corporativa sincroniza o perfil -- e sao ~250 MB de executaveis.
  Base := GetEnvironmentVariable('LOCALAPPDATA');
  if Base = '' then
    Base := TPath.GetHomePath;

  Result := IncludeTrailingPathDelimiter(
    TPath.Combine(Base, 'MultiMigrador\Sistemas'));
  ForceDirectories(Result);
end;

function VersaoExtraida(const ADir: string): string;
begin
  Result := '';
  try
    if TFile.Exists(ADir + MARCADOR) then
      Result := Trim(TFile.ReadAllText(ADir + MARCADOR));
  except
    Result := '';
  end;
end;

procedure ExtrairMigradores;
var
  RS: TResourceStream;
  Zip: TZipFile;
  Dir, NomeArq, Destino, CaminhoNormalizado, DirNormalizado: string;
  Bytes: TBytes;
  i: Integer;
  Projeto: Boolean;
  HouveFalhaCritica: Boolean;
begin
  if FindResource(HInstance, 'MIGRADORES', RT_RCDATA) = 0 then
    Exit;

  Dir := PastaSistemas;
  Projeto := EhAmbienteDeProjeto;

  // Ja extraido nesta versao? Nao faz nada.
  if VersaoExtraida(Dir) = APP_VERSAO then
    Exit;

  // Verifica se há espaço livre em disco antes de descompactar
  if not TemEspacoLivreSuficiente(Dir, MIN_ESPACO_LIVRE_BYTES) then
  begin
    LogarErro('Espaço em disco insuficiente para extrair os migradores em: ' + Dir);
    Exit;
  end;

  HouveFalhaCritica := False;
  RS := TResourceStream.Create(HInstance, 'MIGRADORES', RT_RCDATA);
  try
    Zip := TZipFile.Create;
    try
      Zip.Open(RS, zmRead);
      DirNormalizado := IncludeTrailingPathDelimiter(TPath.GetFullPath(Dir));

      for i := 0 to Zip.FileCount - 1 do
      begin
        NomeArq := Zip.FileName[i];
        // normaliza separadores para Windows
        NomeArq := StringReplace(NomeArq, '/', '\', [rfReplaceAll]);
        Destino := Dir + NomeArq;

        // Sanitização contra Path Traversal (Zip Slip)
        CaminhoNormalizado := TPath.GetFullPath(Destino);
        if not CaminhoNormalizado.StartsWith(DirNormalizado, True) then
        begin
          LogarErro('Tentativa de extração bloqueada fora da pasta de destino: ' + NomeArq);
          Continue;
        end;

        // entrada de diretorio
        if (NomeArq = '') or NomeArq.EndsWith('\') then
        begin
          ForceDirectories(Destino);
          Continue;
        end;

        // Preserva configuracoes locais: um .ini que ja existe na maquina do
        // cliente (ex.: dados de conexao) nao e sobrescrito na atualizacao.
        // Na 1a instalacao ele nao existe, entao e extraido como padrao.
        if SameText(ExtractFileExt(Destino), '.ini') and TFile.Exists(Destino) then
          Continue;

        // Na pasta do projeto, as pastas versionadas SAO a fonte da verdade: e
        // delas que o gerar_recursos.bat monta o pacote. Sobrescrever aqui
        // desfazia o trabalho do desenvolvedor -- trocava-se o exe de um
        // migrador, abria-se o launcher e o exe antigo (o que estava no zip
        // embutido, possivelmente desatualizado) voltava por cima. Nesse modo
        // so completamos o que falta; distribuido continua sobrescrevendo tudo,
        // que e o comportamento necessario para a atualizacao chegar ao cliente.
        if Projeto and TFile.Exists(Destino) then
          Continue;

        // Se o arquivo já existe com o mesmo tamanho descompactado, preserva e pula
        if TFile.Exists(Destino) and (TFile.GetSize(Destino) = Int64(Zip.FileInfo[i].UncompressedSize64)) then
          Continue;

        try
          ForceDirectories(ExtractFilePath(Destino));
          Zip.Read(i, Bytes);
          TFile.WriteAllBytes(Destino, Bytes);
        except
          on E: Exception do
          begin
            // Se o arquivo já existe no destino, a falha ao sobrescrever decorre
            // do arquivo estar aberto em execução no momento. Não é falha crítica.
            if not TFile.Exists(Destino) then
              HouveFalhaCritica := True;
            LogarErro('Falha ao extrair arquivo: ' + NomeArq + ' (' + E.Message + ')');
          end;
        end;
      end;
    finally
      Zip.Free;
    end;
  finally
    RS.Free;
  end;

  // grava o marcador da versao extraida apenas se nao houve falha critica. Se ja existe (oculto),
  // limpa o atributo antes para o WriteAllText conseguir sobrescrever; depois volta a ocultar.
  if not HouveFalhaCritica then
  begin
    try
      if TFile.Exists(Dir + MARCADOR) then
        TFile.SetAttributes(Dir + MARCADOR, []);
      TFile.WriteAllText(Dir + MARCADOR, APP_VERSAO);
      TFile.SetAttributes(Dir + MARCADOR, [TFileAttribute.faHidden]);
      LogarAcao('Pacote de migradores v' + APP_VERSAO + ' extraído com sucesso');
    except
      on E: Exception do
        LogarErro('Erro ao gravar marcador de versão: ' + E.Message);
    end;
  end;
end;

end.
