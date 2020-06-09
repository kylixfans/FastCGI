unit NGINX.FCGIRecord;

/// <summary>
/// A FastCGI Record.
/// </summary>
/// <remarks>
/// See section 3.3 of the FastCGI Specification for details.
/// </remarks>
///
interface

uses
  System.SysUtils, System.Classes, NGINX.FCGIConstants, IdIOHandler, IdGlobal,
  System.Generics.Collections, System.StrUtils;

type
  /// <summary>
  /// Record types, used in the 'type' field of Record.
  /// </summary>
  /// <remarks>
  /// Described in the FastCGI Specification section 8.
  /// </remarks>
  TRecordType = (BeginRequest = FCGI_BEGIN_REQUEST, AbortRequest, EndRequest,
    Params, Stdin, Stdout, Stderr, Data, GetValues, GetValuesResult,
    UnknownType = FCGI_UNKNOWN_TYPE, MaxType = FCGI_MAXTYPE);
  /// <summary>
  /// Protocol status used for requests.
  /// Described in the FastCGI Specification section 8.
  /// </summary>
  TProtocolStatus = (RequestComplete = FCGI_REQUEST_COMPLETE,
    CantMpxConn = FCGI_CANT_MPX_CONN, Overloaded = FCGI_OVERLOADED,
    UnknownRole = FCGI_UNKNOWN_ROLE);

{$M+}

  TFCGIRecord = class
  private
    FIO: TIdIOHandler;
    FVersion: Byte;
    FRecordType: TRecordType;
    FRequestId: Integer;
    FContentLength: Integer;
    FContentData: TMemoryStream;
    procedure ReadBytes(len: Integer);
    function ReadInt16: UInt16;
    function ReadByte: Byte;
    procedure ReadContent(len: Integer);
  published
    /// <summary>
    /// The version byte. Should always equal <see cref="FCGIConstants.FCGI_VERSION_1"/>.
    /// </summary>
    property Version: Byte read FVersion;
    /// <summary>
    /// The <see cref="TRecordType"/> of this record.
    /// </summary>
    property RecordType: TRecordType read FRecordType;
    /// <summary>
    /// The request id associated with this record.
    /// </summary>
    property RequestId: Integer read FRequestId;
    /// <summary>
    /// The length of <see cref="ContentData"/>.
    /// </summary>
    property ContentLength: Integer read FContentLength;
    /// <summary>
    /// The data contained in this record.
    /// </summary>
    property ContentData: TMemoryStream read FContentData;
  public
    constructor Create(io: TIdIOHandler);
    procedure ReadRecord;
  end;

implementation

{ TFCGIRecord }

constructor TFCGIRecord.Create(io: TIdIOHandler);
begin
  FIO := io;
end;

/// <summary>
/// Reads a single byte from the given stream.
/// </summary>
function TFCGIRecord.ReadByte: Byte;
begin
  Result := FIO.ReadByte;
end;

procedure TFCGIRecord.ReadBytes(len: Integer);
var
  buf: TIdBytes;
begin
  SetLength(buf, len);
  FIO.ReadBytes(buf, len);
end;

procedure TFCGIRecord.ReadContent(len: Integer);
begin
  FContentData := TMemoryStream.Create;
  FIO.ReadStream(FContentData, len);
end;

/// <summary>
/// Reads a 16-bit integer from the given stream.
/// </summary>
function TFCGIRecord.ReadInt16: UInt16;
var
  h, l: Byte;
begin
  h := ReadByte;
  l := ReadByte;
  Result := h * 256 + l;
end;

/// <summary>
/// Reads a single Record from the given stream.
/// </summary>
/// <remarks>
/// Returns the retreived record or null if no record could be read.
/// Will block if a partial record is on the stream, until the full record has arrived or a timeout occurs.
/// </remarks>
procedure TFCGIRecord.ReadRecord;
var
  paddingLength: Byte;
begin
  FVersion := ReadByte;
  if FVersion <> FCGI_VERSION_1 then
  begin
    raise Exception.Create
      ('Invalid version number in FastCGI record header. Possibly corrupted data.');
  end;
  case ReadByte of
    1:
      FRecordType := BeginRequest;
    2:
      FRecordType := AbortRequest;
    3:
      FRecordType := EndRequest;
    4:
      FRecordType := Params;
    5:
      FRecordType := Stdin;
    6:
      FRecordType := Stdout;
    7:
      FRecordType := Stderr;
    8:
      FRecordType := Data;
    9:
      FRecordType := GetValues;
    10:
      FRecordType := GetValuesResult;
    11:
      FRecordType := UnknownType;
    12:
      FRecordType := MaxType;
  end;
  FRequestId := ReadInt16;
  FContentLength := ReadInt16;

  paddingLength := ReadByte;
  ReadByte;

  if FContentLength > 0 then
  begin
    ReadContent(FContentLength);
  end;
  if paddingLength > 0 then
  begin
    ReadBytes(paddingLength);
  end;
end;

end.
