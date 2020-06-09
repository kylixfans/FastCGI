# FastCGI for Delphi

This is an implementation of [FastCGI](http://www.fastcgi.com/devkit/doc/fcgi-spec.html) for Delphi, written in Pascal. It implements the parts of the protocol that are necessary to build a simple web application using Delphi.

This means that you can write web applications in Pascal that serve dynamic content.

## License and contributing

This software is distributed under the terms of the MIT license. You can use it for your own projects for free under the conditions specified in LICENSE.

If you have questions, feel free to contact me. Visit [www.mvcxe.com](https://www.mvcxe.com) for my contact details.

If you think you found a bug, you can open an Issue on Github. If you make changes to this library, I would be happy about a pull request.

## Basic usage

The most common usage scenario is to use this library together with a web server nginx. The web server will serve static content and forward HTTP requests for dynamic content to your application.

Have a look at the NGINX.FCGIApplication.TFCGIApplication class for usage examples and more information.

This code example shows how to create a FastCGI application and receive requests:

```pascal
// Create a new FCGIApplication, will accept FastCGI requests
var 
  app: TFCGIApplication;

// Handle requests by responding with a 'Hello World' message
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

app := TFCGIApplication.Create;
app.OnRequestReceived := WebModule.FCGIRequestReceived;
// Start listening on port 19000
app.Run(19000);

```

## Web server configuration

For nginx, use `fastcgi_pass` to pass requests to your FastCGI application:

    location / {
        fastcgi_pass   127.0.0.1:19000; # Pass all requests to port 19000 via FastCGI.
        include fastcgi_params; # (Optional): Set several FastCGI parameters like the remote IP and other metadata.
    }

For more details, refer to your web server documentation for configuration details:

 * [nginx documentation](http://nginx.org/en/docs/http/ngx_http_fastcgi_module.html)
