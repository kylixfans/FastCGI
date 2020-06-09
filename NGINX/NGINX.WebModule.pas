unit NGINX.WebModule;

interface

uses
  System.SysUtils, System.Classes, NGINX.FCGIApplication, NGINX.FCGIRequest,
  NGINX.FCGIResponse, System.Generics.Collections;

type
  TWebModule = class
  private
  public
    procedure FCGIRequestIncoming(const sender: TObject;
      const Request: TFCGIRequest);
    procedure FCGIRequestReceived(const sender: TObject;
      const Request: TFCGIRequest; Response: TFCGIResponse);
  end;

var
  WebModule: TWebModule;

implementation

procedure TWebModule.FCGIRequestIncoming(const sender: TObject;
  const Request: TFCGIRequest);
begin
  WriteLn('RequestIncoming, RequestId=' + IntToStr(Request.RequestId));
end;

procedure TWebModule.FCGIRequestReceived(const sender: TObject;
  const Request: TFCGIRequest; Response: TFCGIResponse);
var
  Content: string;
  item: TPair<string, TBytes>;
begin
  Content := 'Hello World!<br/>这是中文内容<br/>';
  for item in Request.Parameters do
  begin
    Content := Content + ' ' + item.Key + '=' + TEncoding.UTF8.GetString
      (item.Value) + '<br/>';
  end;
  Response.Content := Content;
end;

end.
