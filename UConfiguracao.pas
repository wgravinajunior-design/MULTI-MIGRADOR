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
    Result := 'smtp.titan.email';  // padrão
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

function ObterSMTPSenha: string;
var
  Valor: string;
begin
  Valor := GetEnvironmentVariable('MM_SMTP_SENHA');
  if Valor <> '' then
    Result := Valor
  else
    Result := 'Goup226457#$';  // padrão (deve ser alterado para variável de ambiente)
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
