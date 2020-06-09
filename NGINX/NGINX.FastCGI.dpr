program NGINX.FastCGI;

{$APPTYPE CONSOLE}
{$R *.res}

uses
  System.SysUtils,
  System.Types,
  IPPeerServer,
  IPPeerAPI,
  NGINX.FCGIApplication in 'NGINX.FCGIApplication.pas',
  NGINX.FCGIRequest in 'NGINX.FCGIRequest.pas',
  NGINX.FCGIStream in 'NGINX.FCGIStream.pas',
  NGINX.FCGIRecord in 'NGINX.FCGIRecord.pas',
  NGINX.FCGIConstants in 'NGINX.FCGIConstants.pas',
  NGINX.FCGIResponse in 'NGINX.FCGIResponse.pas',
  ServerConst1 in 'ServerConst1.pas',
  NGINX.WebModule in 'NGINX.WebModule.pas';

function BindPort(APort: Integer): Boolean;
var
  LTestServer: IIPTestServer;
begin
  Result := True;
  try
    LTestServer := PeerFactory.CreatePeer('', IIPTestServer) as IIPTestServer;
    LTestServer.TestOpenPort(APort, nil);
  except
    Result := False;
  end;
end;

function CheckPort(APort: Integer): Integer;
begin
  if BindPort(APort) then
    Result := APort
  else
    Result := 0;
end;

procedure SetPort(const AServer: TFCGIApplication; APort: String);
begin
  if not AServer.Active then
  begin
    APort := APort.Replace(cCommandSetPort, '').Trim;
    if CheckPort(APort.ToInteger) > 0 then
    begin
      AServer.DefaultPort := APort.ToInteger;
      Writeln(Format(sPortSet, [APort]));
    end
    else
      Writeln(Format(sPortInUse, [APort]));
  end
  else
    Writeln(sServerRunning);
  Write(cArrow);
end;

procedure StartServer(const AServer: TFCGIApplication);
begin
  if not AServer.Active then
  begin
    if CheckPort(AServer.DefaultPort) > 0 then
    begin
      Writeln(Format(sStartingServer, [AServer.DefaultPort]));
      AServer.Active := True;
    end
    else
      Writeln(Format(sPortInUse, [AServer.DefaultPort.ToString]));
  end
  else
    Writeln(sServerRunning);
  Write(cArrow);
end;

procedure WriteStatus(const AServer: TFCGIApplication);
begin
  Writeln(sIndyVersion + AServer.Version);
  Writeln(sActive + AServer.Active.ToString(TUseBoolStrs.True));
  Writeln(sPort + AServer.DefaultPort.ToString);
  Write(cArrow);
end;

procedure StopServer(const AServer: TFCGIApplication);
begin
  if AServer.Active then
  begin
    Writeln(sStoppingServer);
    AServer.Active := False;
    Writeln(sServerStopped);
  end
  else
    Writeln(sServerNotRunning);
  Write(cArrow);
end;

procedure WriteCommands;
begin
  Writeln(sCommands);
  Write(cArrow);
end;

procedure RunServer(APort: Integer);
var
  LServer: TFCGIApplication;
  LResponse: string;
begin
  WriteCommands;
  LServer := TFCGIApplication.Create;
  try
    LServer.DefaultPort := APort;
    LServer.OnRequestIncoming := WebModule.FCGIRequestIncoming;
    LServer.OnRequestReceived := WebModule.FCGIRequestReceived;
    while True do
    begin
      Readln(LResponse);
      LResponse := LowerCase(LResponse);
      if LResponse.StartsWith(cCommandSetPort) then
        SetPort(LServer, LResponse)
      else if sametext(LResponse, cCommandStart) then
        StartServer(LServer)
      else if sametext(LResponse, cCommandStatus) then
        WriteStatus(LServer)
      else if sametext(LResponse, cCommandStop) then
        StopServer(LServer)
      else if sametext(LResponse, cCommandHelp) then
        WriteCommands
      else if sametext(LResponse, cCommandExit) then
        if LServer.Active then
        begin
          StopServer(LServer);
          break
        end
        else
          break
      else
      begin
        Writeln(sInvalidCommand);
        Write(cArrow);
      end;
    end;
  finally
    LServer.Free;
  end;
end;

begin
  try
    { TODO -oUser -cConsole Main : Insert code here }
    WebModule := TWebModule.Create;
    RunServer(8044);
    { app := TFCGIApplication.Create;
      try
      app.Run(8044);
      app.OnRequestIncoming := m.AppRequestIncoming;
      app.OnRequestReceived := m.AppRequestReceived;
      ReadLn;
      finally
      app.Free;
      end; }
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;

end.
