unit NGINX.FCGIRequest;

/// <summary>
/// A FastCGI request.
/// </summary>
/// <remarks>
/// A request usually corresponds to a HTTP request that has been received by the webserver (see the [FastCGI specification](http://www.fastcgi.com/devkit/doc/fcgi-spec.html) for details).
/// </remarks>
interface

uses
  System.SysUtils, System.Classes, NGINX.FCGIRecord, IdIOHandler,
  System.Generics.Collections, NGINX.FCGIStream;

type
{$M+}
  TFCGIRequest = class
  private
    FRequestId: Integer;
    FIO: TIdIOHandler;
    FKeepAlive: Boolean;
    FIsOpen: Boolean;
    /// <summary>
    /// Incoming parameter records are stored here, until the parameter stream is closed by the webserver by sending an empty param record.
    /// </summary>
    FParamStream: TMemoryStream;
    FParameters: TDictionary<string, TBytes>;
    FRequestBodyStream: TMemoryStream;
    procedure Param_ReadNameValuePairs;
  protected
  published
    /// <summary>
    /// The id for this request, issued by the webserver
    /// </summary>
    property RequestId: Integer read FRequestId;
    /// <summary>
    /// True iff the webserver set the KeepAlive flag for this request
    /// </summary>
    /// <remarks>
    /// This indicates that the socket used for this request should be left open.
    /// This is used internally by <see cref="TFCGIApplication"/>.
    /// </remarks>
    property KeepAlive: Boolean read FKeepAlive;
    /// <summary>
    /// The FastCGI parameters received by the webserver, in raw byte arrays.
    /// </summary>
    property Parameters: TDictionary<string, TBytes> read FParameters;
    /// <summary>
    /// A stream providing the request body.
    /// </summary>
    /// <remarks>
    /// For POST requests, this will contain the POST variables. For GET requests, this will be empty.
    /// </remarks>
    property RequestBody: TMemoryStream read FRequestBodyStream;
  public
    constructor Create(RequestId: Integer; responseHandler: TIdIOHandler;
      KeepAlive: Boolean);
    function HandleRecord(r: TFCGIRecord): Boolean;
  end;

implementation

{ TFCGIRequest }

/// <summary>
/// Creates a new request. Usually, you don't need to call this.
/// </summary>
/// <remarks> Records are created by <see cref="TFCGIApplication"/> when a new request has been received.</remarks>
constructor TFCGIRequest.Create(RequestId: Integer;
  responseHandler: TIdIOHandler; KeepAlive: Boolean);
begin
  FRequestId := RequestId;
  FIO := responseHandler;
  FKeepAlive := KeepAlive;
  FIsOpen := true;
  FParameters := TDictionary<string, TBytes>.Create;
  FRequestBodyStream := TMemoryStream.Create;
end;

/// <summary>
/// Used internally. Feeds a <see cref="TFCGIRecord">TFCGIRecord</see> to this request for processing.
/// </summary>
/// <param name="TFCGIRecord">The record to feed.</param>
/// <returns>Returns true iff the request is completely received.</returns>
function TFCGIRequest.HandleRecord(r: TFCGIRecord): Boolean;
var
  oldPos: Integer;
begin
  Result := false;
  case r.RecordType of
    TRecordType.Params:
      begin
        if not Assigned(FParamStream) then
          FParamStream := TMemoryStream.Create;
        if r.ContentLength = 0 then
        begin
          // An empty parameter record specifies that all parameters have been transmitted
          FParamStream.Position := 0;
          Param_ReadNameValuePairs;
        end
        else
        begin
          // If the params are not yet finished, write the contents to the ParamStream.
          r.ContentData.Position := 0;
          FParamStream.CopyFrom(r.ContentData, r.ContentLength);
        end;
      end;
    TRecordType.Stdin:
      begin
        if r.ContentLength = 0 then
        begin
          // Finished requests are indicated by an empty stdin record
          Result := true;
        end
        else
        begin
          oldPos := FRequestBodyStream.Position;
          FRequestBodyStream.Seek(0, TSeekOrigin.soEnd);
          r.ContentData.Position := 0;
          FRequestBodyStream.CopyFrom(r.ContentData, r.ContentLength);
          FRequestBodyStream.Position := oldPos;
        end;
      end;
  end;
end;

/// <summary>
/// Tries to read a dictionary of name-value pairs from the given stream
/// </summary>
/// <remarks>
/// This method does not make any attempt to make sure whether this record actually contains a set of name-value pairs.
/// It will return nonsense or throw an EndOfStreamException if the record content does not contain valid name-value pairs.
/// </remarks>
procedure TFCGIRequest.Param_ReadNameValuePairs;
/// <summary>
/// Reads a length from the given stream, which is encoded in one or four bytes.
/// </summary>
/// <remarks>
/// See section 3.4 of the FastCGI specification for details.
/// </remarks>
  function ReadVarLength: UInt16;
  var
    firstByte: Byte;
    b0, b1, b2: Byte;
  begin
    FParamStream.Read(firstByte, 1);
    if firstByte <= 127 then
    begin
      Result := firstByte;
    end
    else
    begin
      FParamStream.Read(b2, 1);
      FParamStream.Read(b1, 1);
      FParamStream.Read(b0, 1);
      Result := UInt16((16777216 * ($7F and firstByte) + 65536 * b2 + 256 *
        b1 + b0));
    end;
  end;

var
  nameLength: UInt16;
  valueLength: UInt16;
  name: TBytes;
  Value: TBytes;
  n: string;
begin
  if not Assigned(FParameters) then
    FParameters := TDictionary<string, TBytes>.Create;
  while FParamStream.Position < FParamStream.Size do
  begin
    nameLength := ReadVarLength;
    valueLength := ReadVarLength;
    // x32 does not allow objects larger than 2GB
    // We do not make the effort to workaround this,
    // but simply throw an error if we encounter sizes beyond this limit.
    if (nameLength >= Integer.MaxValue) or (valueLength >= Integer.MaxValue)
    then
    begin
      raise Exception.Create('Cannot process values larger than 2GB.');
    end;
    SetLength(name, nameLength);
    FParamStream.Read(name, nameLength);
    n := TEncoding.ASCII.GetString(name);
    SetLength(Value, valueLength);
    FParamStream.Read(Value, valueLength);

    if FParameters.ContainsKey(n) then
      FParameters[n] := Value
    else
      FParameters.Add(n, Value);
  end;
end;

end.
