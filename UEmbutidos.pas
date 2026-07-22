unit UEmbutidos;

// Extrai as DLLs do OpenSSL embutidas como recursos (DllsEmbutidas.rc) para a
// pasta do executavel, tornando o exe autossuficiente em qualquer maquina.
// Chamado no inicio do .dpr, antes de qualquer uso do Indy.

interface

procedure ExtrairDLLsEmbutidas;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils;

// Extrai um recurso RCDATA para ADestino. Se ja existe com o mesmo tamanho,
// nao regrava (evita tocar em arquivo possivelmente em uso por outra instancia).
procedure ExtrairRecurso(const ANome, ADestino: string);
var
  RS: TResourceStream;
begin
  if FindResource(HInstance, PChar(ANome), RT_RCDATA) = 0 then
    Exit; // recurso ausente: segue sem erro (comportamento antigo)

  RS := TResourceStream.Create(HInstance, ANome, RT_RCDATA);
  try
    if TFile.Exists(ADestino) and
       (TFile.GetSize(ADestino) = RS.Size) then
      Exit;
    try
      RS.SaveToFile(ADestino);
    except
      // Sem permissao de escrita ou arquivo em uso: se a DLL ja existe,
      // o app segue com ela; senao o envio de e-mail avisara o erro de SSL.
    end;
  finally
    RS.Free;
  end;
end;

procedure ExtrairDLLsEmbutidas;
var
  Dir: string;
begin
  Dir := ExtractFilePath(ParamStr(0));
  ExtrairRecurso('LIBEAY32', Dir + 'libeay32.dll');
  ExtrairRecurso('SSLEAY32', Dir + 'ssleay32.dll');
end;

end.
