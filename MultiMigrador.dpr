program MultiMigrador;

uses
  Vcl.Forms,
  UPrincipal in 'UPrincipal.pas' {FormPrincipal},
  UReportarProblema in 'UReportarProblema.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'Multi Migrador';
  Application.CreateForm(TFormPrincipal, FormPrincipal);
  Application.Run;
end.
