unit NGINX.FCGIApplication;

/// <summary>
/// Main FastCGI listener class.
/// </summary>
///
/// <remarks>
/// This class manages a connection to a webserver by listening on a given port on localhost and receiving FastCGI
/// requests by webserver nginx.
///
/// In FastCGI terms, this class implements the responder role. Refer to section 6.2 of the FastCGI specification
/// for details.
///
/// Use <see cref="OnRequestReceived"/> to get notified of received requests. You can call <see cref="Run(int)"/> to
/// enter an infinite loopand let the app handle everything.
/// Alternatively, if you want to control the execution flow by yourself, call <see cref="Active:=true"/> to start
/// accepting connections. Then repeatedly call <see cref="FCGIExecute"/> to handle incoming requests.
///
/// If you want to manage the socket connection details by yourself, or for testing purposes,
/// you can also call <see cref="FCGIExecute(AContext)"/> instead of any of the above methods.
///
/// See the below example to learn how to accept requests.
/// For more detailed information, have a look at the <see cref="TFCGIRequest"/><see cref="TFCGIResponse"/> class.
///
/// If you need to fiddle with the FastCGI packets itself, see the <see cref="TFCGIRecord"/> class and read the
/// [FastCGI specification](http://www.fastcgi.com/devkit/doc/fcgi-spec.html).
/// </remarks>

interface

uses
  System.SysUtils, System.Generics.Collections, System.Classes,
  NGINX.FCGIRequest, NGINX.FCGIStream, NGINX.FCGIRecord,
  NGINX.FCGIConstants,
  IdBaseComponent, IdComponent, IdCustomTCPServer, IdSocksServer, IdTCPServer,
  IdContext, IdGlobal, NGINX.FCGIResponse;

const
  _Timeout = 5000;

type
  TFCGIRequestIncoming = procedure(const sender: TObject;
    const Request: TFCGIRequest) of object;
  TFCGIRequestReceived = procedure(const sender: TObject;
    const Request: TFCGIRequest; Response: TFCGIResponse) of object;

{$M+}

  TFCGIApplication = class
  private
    FOnRequestReceived: TFCGIRequestReceived;
    FOnRequestIncoming: TFCGIRequestIncoming;
    FTimeout: Integer;
    FListeningSocket: TIdTCPServer;
    /// <summary>
    /// A dictionary of all open <see cref="TFCGIRequest">TFCGIRequest</see>, indexed by the FastCGI request id.
    /// </summary>
    Requests: TDictionary<Integer, TFCGIRequest>;
    FDefaultPort: Integer;
    function GetConnected: Boolean;
    procedure SetTimeout(const Value: Integer);
    function GetTimeout: Integer;
    procedure StopListening;
    procedure FCGIExecute(AContext: TIdContext);
    procedure SetDefaultPort(const Value: Integer);
    procedure SetActive(const Value: Boolean);
    function GetVersion: string;
  protected
    property ListeningSocket: TIdTCPServer read FListeningSocket;
  published
    property Active: Boolean read GetConnected write SetActive;
    property Timeout: Integer read GetTimeout write SetTimeout;
    property DefaultPort: Integer read FDefaultPort write SetDefaultPort;
    property Version: string read GetVersion;
    /// <summary>
    /// Will be called when a request has been fully received.
    /// </summary>
    property OnRequestReceived: TFCGIRequestReceived read FOnRequestReceived
      write FOnRequestReceived;
    /// <summary>
    /// Will be called when a new request is incoming, before it has been fully received.
    /// </summary>
    property OnRequestIncoming: TFCGIRequestIncoming read FOnRequestIncoming
      write FOnRequestIncoming;
  public
    constructor Create;
    destructor Destory;
    procedure Run(port: Integer);
  end;

implementation

{ TFCGIApplication }

function TFCGIApplication.GetConnected: Boolean;
begin
  Result := FListeningSocket.Active;
end;

/// <summary>
/// The read/write timeouts in miliseconds for the listening socket, the connections, and the streams.
/// </summary>
/// <remarks>Zero or -1 mean infinite timeout.</remarks>
function TFCGIApplication.GetTimeout: Integer;
begin
  if FTimeout = 0 then
  begin
    FTimeout := _Timeout;
  end;
  Result := FTimeout;
end;

function TFCGIApplication.GetVersion: string;
begin
  Result := FListeningSocket.Version;
end;

/// <summary>
/// Starts listening for connections on the given port.
/// </summary>
/// <remarks>
/// Will only accept connections from localhost.
/// </remarks>
procedure TFCGIApplication.Run(port: Integer);
begin
  FListeningSocket.DefaultPort := port;
  FListeningSocket.Active := True;
end;

constructor TFCGIApplication.Create;
begin
  Requests := TDictionary<Integer, TFCGIRequest>.Create;
  FListeningSocket := TIdTCPServer.Create(nil);
  FListeningSocket.OnExecute := FCGIExecute;
end;

destructor TFCGIApplication.Destory;
begin
  StopListening;
  Requests.Free;
  FListeningSocket.Free;
end;

/// <summary>
/// Tries to read and handle a <see cref="TFCGIRecord"/> from inputStream and writes responses to outputStream.
/// </summary>
procedure TFCGIApplication.FCGIExecute(AContext: TIdContext);
var
  req: TFCGIRequest;
  Response: TFCGIResponse;
  r: TFCGIRecord;
  role: Integer;
  flags: Byte;
  keepAlive: Boolean;
  ValuesResultStream: TFCGIStream;
begin
  with AContext.Connection do
  begin
    IOHandler.ReadTimeout := GetTimeout;
    // if not IOHandler.Readable(0) then
    // begin
    // Exit;
    // end;
    r := TFCGIRecord.Create(IOHandler);
  end;
  try
    r.ReadRecord;
    if r.RecordType = TRecordType.BeginRequest then
    begin
      if Requests.ContainsKey(r.RequestId) then
      begin
        Requests.Remove(r.RequestId);
      end;
      BeginRequestData(r.ContentData, role, flags);
      if (flags and FCGI_KEEP_CONN) <> 0 then
        keepAlive := True
      else
        keepAlive := False;

      req := TFCGIRequest.Create(r.RequestId, AContext.Connection.IOHandler,
        keepAlive);
      Requests.Add(r.RequestId, req);
      if Assigned(FOnRequestIncoming) then
        FOnRequestIncoming(Self, req);
    end
    else if (r.RecordType = TRecordType.AbortRequest) or
      (r.RecordType = TRecordType.EndRequest) then
    begin
      Requests.Remove(r.RequestId);
    end
    else if r.RecordType = TRecordType.GetValues then
    begin
      ValuesResultStream := TFCGIStream.Create(0);
      try
        ValuesResultStream.ValuesResult(1, 1, False);
        ValuesResultStream.stream.Position := 0;
        AContext.Connection.IOHandler.Write(ValuesResultStream.stream,
          ValuesResultStream.StreamLength);
        AContext.Connection.IOHandler.Close;
      finally
        ValuesResultStream.Free;
      end;
    end
    else
    begin
      if Requests.ContainsKey(r.RequestId) then
      begin
        req := Requests[r.RequestId];
        if req.HandleRecord(r) then
        begin
          if Assigned(FOnRequestReceived) then
          begin
            Response := TFCGIResponse.Create(r.RequestId,
              AContext.Connection.IOHandler);
            try
              FOnRequestReceived(Self, req, Response);
              if not Response.IsClose then
              begin
                Response.Flush;
              end;
            finally
              Response.Free;
            end;
          end;
          with AContext.Connection do
          begin
            IOHandler.Close;
            if not req.keepAlive then
            begin
              AContext.Connection.Disconnect;
            end;
          end;
          Requests.Remove(r.RequestId);
        end;
      end;
    end;
  finally
    r.Free;
  end;
end;

/// <summary>
/// True iff this application is currently connected to a webserver.
/// </summary>
procedure TFCGIApplication.SetActive(const Value: Boolean);
begin
  FListeningSocket.Active := Value;
end;

procedure TFCGIApplication.SetDefaultPort(const Value: Integer);
begin
  FDefaultPort := Value;
  FListeningSocket.DefaultPort := FDefaultPort;
end;

procedure TFCGIApplication.SetTimeout(const Value: Integer);
begin
  FTimeout := Value;
end;

/// <summary>
/// Stops listening for incoming connections.
/// </summary>
procedure TFCGIApplication.StopListening;
begin
  if FListeningSocket <> nil then
  begin
    FListeningSocket.Active := False;
  end;
end;

end.
