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

procedure ExtrairMigradores;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, System.Zip,
  UAtualizador;

const
  MARCADOR = '.migradores.ver';

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

  Dir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));

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

  // grava o marcador da versao extraida
  try
    TFile.WriteAllText(Dir + MARCADOR, APP_VERSAO);
    {$WARN SYMBOL_PLATFORM OFF}
    FileSetAttr(Dir + MARCADOR, faHidden);
    {$WARN SYMBOL_PLATFORM ON}
  except
    // opcional; ignora falha
  end;
end;

end.
