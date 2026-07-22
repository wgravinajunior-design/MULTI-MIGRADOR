program MultiMigrador;

uses
  Vcl.Forms,
  UPrincipal in 'UPrincipal.pas' {FormPrincipal},
  UReportarProblema in 'UReportarProblema.pas',
  UAtualizador in 'UAtualizador.pas',
  UEmbutidos in 'UEmbutidos.pas';

{$R *.res}
{$R DllsEmbutidas.res}

begin
  // Garante as DLLs do OpenSSL ao lado do exe (extraidas dos recursos embutidos)
  ExtrairDLLsEmbutidas;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'Multi Migrador';
  Application.CreateForm(TFormPrincipal, FormPrincipal);
  Application.Run;
end.
