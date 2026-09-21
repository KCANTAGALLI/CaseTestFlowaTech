namespace StatusApi.Middleware;

public class RequestLoggingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestLoggingMiddleware> _logger;

    public RequestLoggingMiddleware(RequestDelegate next, ILogger<RequestLoggingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var path = context.Request.Path.Value ?? "/";
        var method = context.Request.Method;

        await _next(context);

        _logger.LogInformation("{Method} {Path} -> {StatusCode}",
            method, path, context.Response.StatusCode);
    }
}
