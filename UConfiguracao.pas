unit UConfiguracao;

// Carregamento seguro de configurações (SMTP, etc).
// Tenta carregar de variáveis de ambiente primeiro, depois de arquivo de configuração.

interface

function ObterSMTPHost: string;
function ObterSMTPPorta: Integer;
function ObterSMTPUsuario: string;
function ObterSMTPSenha: string;
function ObterSMTPDestino: string;

implementation

uses
  System.SysUtils, System.IOUtils;

function ObterSMTPHost: string;
var
  Valor: string;
begin
  Valor := GetEnvironmentVariable('MM_SMTP_HOST');
  if Valor <> '' then
    Result := Valor
  else
    Result := 'email-ssl.com.br';  // padrão (Locaweb, SSL implícito na 465)
end;

function ObterSMTPPorta: Integer;
var
  Valor: string;
begin
  Valor := GetEnvironmentVariable('MM_SMTP_PORTA');
  if Valor <> '' then
    Result := StrToIntDef(Valor, 465)
  else
    Result := 465;  // padrão
end;

function ObterSMTPUsuario: string;
var
  Valor: string;
begin
  Valor := GetEnvironmentVariable('MM_SMTP_USUARIO');
  if Valor <> '' then
    Result := Valor
  else
    Result := 'migracao@goupsistemas.com';  // padrão
end;

// Função interna para desofuscação em tempo de execução
function DesofuscarPadrao(const AHex: string; const AChave: Byte = $5A): string;
var
  i: Integer;
  B: Byte;
  Bytes: TBytes;
begin
  SetLength(Bytes, Length(AHex) div 2);
  for i := 0 to Length(Bytes) - 1 do
  begin
    B := StrToIntDef('$' + Copy(AHex, (i * 2) + 1, 2), 0);
    Bytes[i] := B xor AChave;
  end;
  Result := TEncoding.UTF8.GetString(Bytes);
end;

function ObterSMTPSenha: string;
var
  Valor: string;
begin
  Valor := GetEnvironmentVariable('MM_SMTP_SENHA');
  if Valor <> '' then
    Result := Valor
  else
    Result := DesofuscarPadrao('1D352F2A68686C6E6F6D797E');  // 'Goup226457#$' ofuscado
end;

function ObterSMTPDestino: string;
var
  Valor: string;
begin
  Valor := GetEnvironmentVariable('MM_SMTP_DESTINO');
  if Valor <> '' then
    Result := Valor
  else
    Result := 'migracao@goupsistemas.com';  // padrão
end;

end.
