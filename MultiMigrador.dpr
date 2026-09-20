program MultiMigrador;

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms,
  UPrincipal in 'UPrincipal.pas' {FormPrincipal},
  UReportarProblema in 'UReportarProblema.pas',
  UAtualizador in 'UAtualizador.pas',
  UEmbutidos in 'UEmbutidos.pas',
  UMigradores in 'UMigradores.pas',
  UCrash in 'UCrash.pas',
  ULogger in 'ULogger.pas',
  UConfiguracao in 'UConfiguracao.pas',
  UNotificacoes in 'UNotificacoes.pas';

{$R *.res}
{$R DllsEmbutidas.res}

var
  HMutex: THandle;
  HOutraJanela: HWND;
  Tentativa: Integer;
  EhReinicioAtualizacao: Boolean;
begin
  EhReinicioAtualizacao := FindCmdLineSwitch('updated') or FindCmdLineSwitch('restart');

  // Instância única: se for reinício de atualização, aguarda até 3s o encerramento do processo anterior
  for Tentativa := 1 to 30 do
  begin
    HMutex := CreateMutex(nil, True, 'MultiMigrador_SingleInstance_Mutex');
    if (HMutex <> 0) and (GetLastError = ERROR_ALREADY_EXISTS) then
    begin
      CloseHandle(HMutex);
      HMutex := 0;

      if EhReinicioAtualizacao then
      begin
        Sleep(100);
        Continue;
      end;

      HOutraJanela := FindWindow('TFormPrincipal', 'Multi Migrador');
      if HOutraJanela <> 0 then
      begin
        ShowWindow(HOutraJanela, SW_RESTORE);
        SetForegroundWindow(HOutraJanela);
      end;
      Exit;
    end
    else
      Break;
  end;

  try
    Application.Initialize;
    ConfigurarCrashHandler;
    LimparLogsAntigos;

    // Extrai recursos embutidos ao lado do exe (DLLs do OpenSSL e os migradores),
    // deixando o launcher autossuficiente em qualquer máquina.
    ExtrairDLLsEmbutidas;
    ExtrairMigradores;

    Application.MainFormOnTaskbar := True;
    Application.Title := 'Multi Migrador';
    Application.CreateForm(TFormPrincipal, FormPrincipal);
    Application.Run;
  finally
    if HMutex <> 0 then
      CloseHandle(HMutex);
  end;
end.
