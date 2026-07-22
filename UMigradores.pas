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
  UAtualizador;

{$WARN SYMBOL_PLATFORM OFF}

const
  MARCADOR = '.migradores.ver';

function EhAmbienteDeProjeto: Boolean;
var
  Dir: string;
begin
  Dir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  Result := TFile.Exists(Dir + 'MultiMigrador.dpr') or
            TFile.Exists(Dir + 'MultiMigrador.dproj');
end;

function PastaSistemas: string;
begin
  if EhAmbienteDeProjeto then
    Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)))
  else
  begin
    Result := IncludeTrailingPathDelimiter(
      TPath.Combine(TPath.GetHomePath, 'MultiMigrador\Sistemas'));
    ForceDirectories(Result);
  end;
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
  Dir, NomeArq, Destino: string;
  Bytes: TBytes;
  i: Integer;
begin
  if FindResource(HInstance, 'MIGRADORES', RT_RCDATA) = 0 then
    Exit;

  Dir := PastaSistemas;

  // Ja extraido nesta versao? Nao faz nada.
  if VersaoExtraida(Dir) = APP_VERSAO then
    Exit;

  RS := TResourceStream.Create(HInstance, 'MIGRADORES', RT_RCDATA);
  try
    Zip := TZipFile.Create;
    try
      Zip.Open(RS, zmRead);
      for i := 0 to Zip.FileCount - 1 do
      begin
        NomeArq := Zip.FileName[i];
        // normaliza separadores para Windows
        NomeArq := StringReplace(NomeArq, '/', '\', [rfReplaceAll]);
        Destino := Dir + NomeArq;

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

        try
          ForceDirectories(ExtractFilePath(Destino));
          Zip.Read(i, Bytes);
          TFile.WriteAllBytes(Destino, Bytes);
        except
          // arquivo em uso ou sem permissao: ignora e segue com os demais
        end;
      end;
    finally
      Zip.Free;
    end;
  finally
    RS.Free;
  end;

  // grava o marcador da versao extraida. Se ja existe (oculto), limpa o atributo
  // antes para o WriteAllText conseguir sobrescrever; depois volta a ocultar.
  try
    if TFile.Exists(Dir + MARCADOR) then
      TFile.SetAttributes(Dir + MARCADOR, []);
    TFile.WriteAllText(Dir + MARCADOR, APP_VERSAO);
    TFile.SetAttributes(Dir + MARCADOR, [TFileAttribute.faHidden]);
  except
    // opcional; ignora falha
  end;
end;

end.
