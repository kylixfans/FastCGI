unit NGINX.FCGIStream;

/// <summary>
/// The stream where responses to this request should be written to.
/// Only write FastCGI records here, not the raw response body. Use <see cref="FCGIResponse.SendRaw"/> for sending response data.
/// </summary>

interface

uses
  System.SysUtils, System.Classes, NGINX.FCGIConstants, NGINX.FCGIRecord,
  System.Generics.Collections, System.StrUtils;

type
{$M+}
  TFCGIStream = class
  private
    FRequestId: Integer;
    FVersion: Integer;
    Fstream: TBytesStream;
    FContentLength: Integer;
    FStreamLength: Integer;
    FRecordType: TRecordType;
    procedure WriteInt16(v: UInt16);
    procedure CreateResponse(data: TBytes);
  published
    property StreamLength: Integer read FStreamLength;
    property stream: TBytesStream read Fstream write Fstream;
  public
    constructor Create(requestId: Integer);
    procedure Response(data: TBytes);
    procedure EndRequest;
    procedure ValuesResult(maxConnections: Integer; maxRequests: Integer;
      multiplexing: Boolean);
  end;

procedure BeginRequestData(stream: TStream; var role: Integer; var flags: Byte);

implementation

procedure BeginRequestData(stream: TStream; var role: Integer; var flags: Byte);
var
  h, l: Byte;
begin
  stream.Position := 0;
  // ReadInt16
  // stream.Read(h, 1);
  // stream.Read(l, 1);
  // role := h * 256 + l;
  stream.Read(role, 1);
  // ReadByte
  stream.Read(flags, 1);
end;

{ TFCGIStream }

constructor TFCGIStream.Create(requestId: Integer);
begin
  FRequestId := requestId;
  FVersion := FCGI_VERSION_1;
  Fstream := TBytesStream.Create;
end;

/// <summary>
/// Writes this record to the given stream.
/// </summary>
/// <returns>Returns the number of bytes written.</returns>
procedure TFCGIStream.CreateResponse(data: TBytes);
var
  b: Byte;
begin
  if FContentLength > 65535 then
  begin
    raise Exception.Create('Cannot send a record with more that 65535 bytes.');
  end;
  Fstream.Clear;
  Fstream.Write(FVersion, 1);

  Fstream.Write(FRecordType, 1);
  WriteInt16(FRequestId);
  WriteInt16(FContentLength);
  // No padding
  b := 0;
  Fstream.Write(b, 1);
  // Reserved byte
  Fstream.Write(b, 1);
  if FContentLength > 0 then
  begin
    Fstream.Write(data, FContentLength);
  end;
  FStreamLength := FCGI_HEADER_LEN + FContentLength;
end;

/// <summary>
/// Creates a EndRequest record with the given request id
/// </summary>
procedure TFCGIStream.EndRequest;
var
  content: TBytes;
begin
  FContentLength := 8;
  SetLength(content, FContentLength);
  content[0] := 0;
  content[1] := 0;
  content[2] := 0;
  content[3] := 0;

  // protocolStatus
  content[4] := Byte(TProtocolStatus.RequestComplete);

  // reserved bytes
  content[5] := 0;
  content[6] := 0;
  content[7] := 0;
  FRecordType := TRecordType.EndRequest;
  CreateResponse(content);
end;

/// <summary>
/// Creates a GetValuesResult record from the given config values.
/// </summary>
procedure TFCGIStream.ValuesResult(maxConnections, maxRequests: Integer;
  multiplexing: Boolean);
var
  nameValuePairs: TDictionary<string, TBytes>;

  vstream: TBytesStream;
  nameValuePair: TPair<string, TBytes>;
  name: string;
  nameBuf, value: TBytes;
  /// <summary>
  /// Writes a length from the given stream, which is encoded in one or four bytes.
  /// </summary>
  /// <remarks>
  /// See section 3.4 of the FastCGI specification for details.
  /// </remarks>
  procedure WriteVarLength(len: UInt32);
  var
    b: Byte;
  begin
    if len <= 127 then
      stream.Write(Byte(len), 1)
    else
    begin
      b := Byte($80 or len div 16777216);
      stream.Write(b, 1);
      b := Byte(len div 65536);
      stream.Write(b, 1);
      b := Byte(len div 256);
      stream.Write(b, 1);
      stream.Write(Byte(len), 1);
    end;
  end;

begin
  nameValuePairs := TDictionary<string, TBytes>.Create();
  try
    nameValuePairs.Add(FCGI_MAX_CONNS,
      TEncoding.ASCII.GetBytes(IntToStr(maxConnections)));
    nameValuePairs.Add(FCGI_MAX_REQS,
      TEncoding.ASCII.GetBytes(IntToStr(maxRequests)));
    nameValuePairs.Add(FCGI_MPXS_CONNS,
      TEncoding.ASCII.GetBytes(IfThen(multiplexing, '1', '0')));
    FRecordType := TRecordType.GetValuesResult;

    vstream := TBytesStream.Create;
    try
      for nameValuePair in nameValuePairs do
      begin
        name := nameValuePair.Key;
        nameBuf := TEncoding.ASCII.GetBytes(name);
        value := nameValuePair.value;
        WriteVarLength(Length(nameBuf));
        WriteVarLength(Length(value));
        stream.Write(nameBuf, 0, Length(nameBuf));
        stream.Write(value, 0, Length(value));
      end;
      FContentLength := stream.Size;
      CreateResponse(stream.Bytes);
    finally
      vstream.Free;
    end;
  finally
    nameValuePairs.Free;
  end;
end;

/// <summary>
/// Creates a Stdout record from the given data and request id
/// </summary>
procedure TFCGIStream.Response(data: TBytes);
begin
  FContentLength := Length(data);
  FRecordType := TRecordType.Stdout;
  CreateResponse(data);
end;

/// <summary>
/// Writes a 16-bit integer to the given stream.
/// </summary>
procedure TFCGIStream.WriteInt16(v: UInt16);
var
  b1, b2: Byte;
begin
  b1 := Byte(v div 256);
  b2 := Byte(v);
  Fstream.Write(b1, 1);
  Fstream.Write(b2, 1);
end;

end.
