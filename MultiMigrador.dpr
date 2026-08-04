program MultiMigrador;

uses
  Vcl.Forms,
  UPrincipal in 'UPrincipal.pas' {FormPrincipal},
  UReportarProblema in 'UReportarProblema.pas',
  UAtualizador in 'UAtualizador.pas',
  UEmbutidos in 'UEmbutidos.pas',
  UMigradores in 'UMigradores.pas';

{$R *.res}
{$R DllsEmbutidas.res}

begin
  // Extrai recursos embutidos ao lado do exe (DLLs do OpenSSL e os migradores),
  // deixando o launcher autossuficiente em qualquer maquina.
  ExtrairDLLsEmbutidas;
  ExtrairMigradores;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'Multi Migrador';
  Application.CreateForm(TFormPrincipal, FormPrincipal);
  Application.Run;
end.
