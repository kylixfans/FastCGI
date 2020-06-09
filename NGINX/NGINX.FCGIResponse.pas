unit NGINX.FCGIResponse;

/// <summary>
/// A FastCGI response.
/// </summary>
/// <remarks>
/// You will probably want to use <see cref="SendRaw"/> or its helper methods to output a response and then call <see cref="Flush"/>. Use <see cref="TFCGIApplication.OnRequestReceived"/> to be notified of new requests.
///
/// Remember to call <see cref="Flush"/> when you wrote the complete response.
/// </remarks>
///
interface

uses
  System.SysUtils, System.Classes, NGINX.FCGIRecord, IdIOHandler,
  System.Generics.Collections, NGINX.FCGIStream;

type
{$M+}
  TFCGIResponse = class
  private
    FRequestId: Integer;
    FIO: TIdIOHandler;
    FIsClose: Boolean;
    FHeader: TDictionary<string, string>;
    FHttpStatusCode: Integer;
    FHttpVersion: string;
    FContent: string;
    FCharset: string;
    FContentType: string;
    procedure SendContent;
    procedure SetContent(const Value: string);
    procedure SetHeader(const Value: TDictionary<string, string>);
    procedure SetHttpStatusCode(const Value: Integer);
    procedure SetHttpVersion(const Value: string);
    procedure SetCharset(const Value: string);
    procedure SetContentType(const Value: string);
  protected
  published
    property HttpVersion: string read FHttpVersion write SetHttpVersion;
    property HttpStatusCode: Integer read FHttpStatusCode
      write SetHttpStatusCode;
    property Header: TDictionary<string, string> read FHeader write SetHeader;
    property Content: string read FContent write SetContent;
    property IsClose: Boolean read FIsClose;
    property ContentType: string read FContentType write SetContentType;
    property Charset: string read FCharset write SetCharset;
  public
    constructor Create(requestId: Integer; responseHandler: TIdIOHandler);
    procedure Send(const data: TBytes); overload;
    procedure Send(const data: TStream); overload;
    procedure Send(const data: string); overload;
    procedure SendRaw(const rawdata: TBytes);
    procedure Flush;
  end;

implementation

{ TFCGIResponse }

constructor TFCGIResponse.Create(requestId: Integer;
  responseHandler: TIdIOHandler);
begin
  FRequestId := requestId;
  FIO := responseHandler;
  FHttpVersion := 'HTTP/1.1';
  FHttpStatusCode := 200;
  FHeader := TDictionary<string, string>.Create;
  ContentType := 'text/html';
  Charset := 'utf-8';

  FHeader.Add('X-Powered-By', 'MVCXE.NGINX.FCGI');
  FIsClose := false;
end;

procedure TFCGIResponse.Flush;
begin
  if not FIsClose then
    SendContent;
  FIsClose := true;
  FIO.Close;
end;

procedure TFCGIResponse.Send(const data: TStream);
var
  s: string;
  item: TPair<string, string>;
  bs: TBytesStream;
begin
  s := FHttpVersion + ' ' + IntToStr(FHttpStatusCode) + ' OK'#10;
  for item in FHeader do
  begin
    s := s + item.Key + ':' + item.Value + #10;
  end;
  s := s + #10;
  bs := TBytesStream.Create(TEncoding.Default.GetBytes(s));
  bs.Write(data, data.Size);
  SendRaw(bs.Bytes);
end;

/// <summary>
/// Appends data to the response body.
/// </summary>
/// <remarks>
/// The given data will be sent immediately to the webserver as a single stdout record.
/// </remarks>
/// <param name="data">The data to append.</param>
procedure TFCGIResponse.Send(const data: TBytes);
var
  s: string;
  item: TPair<string, string>;
  bs: TBytesStream;
begin
  s := FHttpVersion + ' ' + IntToStr(FHttpStatusCode) + ' OK'#10;
  for item in FHeader do
  begin
    s := s + item.Key + ':' + item.Value + #10;
  end;
  s := s + #10;
  bs := TBytesStream.Create(TEncoding.Default.GetBytes(s));
  bs.Write(data, Length(data));
  SendRaw(bs.Bytes);
end;

/// <summary>
/// Appends an ASCII string to the response body.
/// </summary>
/// <remarks>
/// This is a helper function, it converts the given string to ASCII bytes and feeds it to <see cref="SendRaw"/>.
/// </remarks>
/// <param name="data">The string to append, encoded in Charset.</param>
procedure TFCGIResponse.Send(const data: string);
var
  s: string;
  item: TPair<string, string>;
begin
  s := FHttpVersion + ' ' + IntToStr(FHttpStatusCode) + ' OK'#10;
  for item in FHeader do
  begin
    s := s + item.Key + ':' + item.Value + #10;
  end;
  s := s + #10 + data;
  // todo: Encoding
  if SameText(FCharset, 'utf8') or SameText(FCharset, 'utf-8') then
  begin
    SendRaw(TEncoding.UTF8.GetBytes(s));
  end
  else
  begin
    SendRaw(TEncoding.Default.GetBytes(s));
  end;
end;

procedure TFCGIResponse.SendContent;
begin
  Send(Content);
end;

/// <summary>
/// Used internally. Writes the record to the given stream. Used for sending records to the webserver.
/// </summary>
procedure TFCGIResponse.SendRaw(const rawdata: TBytes);
var
  remainingLength: Integer;
  response: TFCGIStream;
  buf64kb: TBytes;
  offset: Integer;
begin
  response := TFCGIStream.Create(FRequestId);
  try
    remainingLength := Length(rawdata);
    if remainingLength <= 65535 then
    begin
      response.response(rawdata);
      response.stream.Position := 0;
      FIO.Write(response.stream, response.StreamLength);
    end
    else
    begin
      SetLength(buf64kb, 65535);
      offset := 0;
      while remainingLength > 65535 do
      begin
        buf64kb := Copy(rawdata, offset, 65535);
        response.response(buf64kb);
        response.stream.Position := 0;
        FIO.Write(response.stream, response.StreamLength);
        offset := offset + 65535;
        remainingLength := remainingLength - 65535;
      end;
      SetLength(buf64kb, remainingLength);
      buf64kb := Copy(rawdata, offset, remainingLength);
      response.response(buf64kb);
      response.stream.Position := 0;
      FIO.Write(response.stream, response.StreamLength);
      SetLength(buf64kb, 0);
    end;
    // 0
    SetLength(buf64kb, 0);
    response.response(buf64kb);
    response.stream.Position := 0;
    FIO.Write(response.stream, response.StreamLength);
    response.EndRequest;
    response.stream.Position := 0;
    FIO.Write(response.stream, response.StreamLength);
    FIsClose := true;
  finally
    response.Free;
  end;
end;

procedure TFCGIResponse.SetCharset(const Value: string);
var
  s: string;
begin
  FCharset := Value;
  if FCharset <> '' then
  begin
    s := '; charset=' + FCharset;
    if FHeader.ContainsKey('Content-Type') then
      FHeader['Content-Type'] := FContentType + s
    else
      FHeader.Add('Content-Type', FContentType + s);
  end;
end;

procedure TFCGIResponse.SetContentType(const Value: string);
var
  s: string;
begin
  FContentType := Value;
  if FCharset <> '' then
  begin
    s := '; charset=' + FCharset;
  end;
  if FHeader.ContainsKey('Content-Type') then
    FHeader['Content-Type'] := FContentType + s
  else
    FHeader.Add('Content-Type', FContentType + s);
end;

procedure TFCGIResponse.SetContent(const Value: string);
begin
  FContent := Value;
end;

procedure TFCGIResponse.SetHeader(const Value: TDictionary<string, string>);
begin
  FHeader := Value;
end;

procedure TFCGIResponse.SetHttpStatusCode(const Value: Integer);
begin
  FHttpStatusCode := Value;
end;

procedure TFCGIResponse.SetHttpVersion(const Value: string);
begin
  FHttpVersion := Value;
end;

end.
