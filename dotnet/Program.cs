using System.Diagnostics;
using System.Text.Json;
using Serilog;
using Serilog.Templates;

// Structured JSON logging via Serilog's ExpressionTemplate, shaped to the
// shared schema: timestamp, level, service, message + request fields.
Log.Logger = new LoggerConfiguration()
    .Enrich.FromLogContext()
    .MinimumLevel.Information()
    .WriteTo.Console(new ExpressionTemplate(
        "{ {timestamp: @t, level: @l, service: 'dotnet', message: @m, method: method, path: path, status_code: status_code, duration_ms: duration_ms, upstream: upstream, error: error} }\n"))
    .CreateLogger();

var builder = WebApplication.CreateBuilder(args);
builder.Host.UseSerilog();
var app = builder.Build();

const string upstreamName = "ruby";

app.MapGet("/dotnet", async (HttpContext context) =>
{
    var start = Stopwatch.GetTimestamp();
    var method = context.Request.Method;
    var path = context.Request.Path.ToString();
    Log.ForContext("method", method).ForContext("path", path).Information("request received");

    var serviceUrl = Environment.GetEnvironmentVariable("RUBY_SERVICE_URL");
    if (string.IsNullOrEmpty(serviceUrl))
    {
        await WriteError(context, method, path, start, "RUBY_SERVICE_URL is not set");
        return;
    }

    using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
    HttpResponseMessage upstream;
    try
    {
        Log.ForContext("upstream", upstreamName).Information("calling upstream");
        upstream = await client.GetAsync(serviceUrl);
    }
    catch (Exception ex)
    {
        await WriteError(context, method, path, start, ex.Message);
        return;
    }

    if (!upstream.IsSuccessStatusCode)
    {
        await WriteError(context, method, path, start, $"upstream returned status {(int)upstream.StatusCode}");
        return;
    }

    var upstreamBody = await upstream.Content.ReadAsStringAsync();
    Log.ForContext("upstream", upstreamName)
       .ForContext("status_code", (int)upstream.StatusCode)
       .Information("upstream responded");

    var envelope = new Dictionary<string, object?>
    {
        ["service"] = "dotnet",
        ["message"] = "Hello from dotnet",
        ["status"] = "ok",
        ["timestamp"] = DateTime.UtcNow.ToString("o"),
        ["upstream"] = JsonSerializer.Deserialize<JsonElement>(upstreamBody),
    };

    context.Response.ContentType = "application/json";
    await context.Response.WriteAsync(JsonSerializer.Serialize(envelope));

    Log.ForContext("method", method).ForContext("path", path)
       .ForContext("status_code", 200)
       .ForContext("duration_ms", (long)Stopwatch.GetElapsedTime(start).TotalMilliseconds)
       .Information("request completed");
});

app.Run();

static async Task WriteError(HttpContext context, string method, string path, long start, string error)
{
    Log.ForContext("upstream", "ruby").ForContext("error", error).Error("upstream call failed");

    var envelope = new Dictionary<string, object?>
    {
        ["service"] = "dotnet",
        ["message"] = "Hello from dotnet",
        ["status"] = "error",
        ["timestamp"] = DateTime.UtcNow.ToString("o"),
        ["upstream"] = null,
        ["error"] = error,
    };

    context.Response.StatusCode = 502;
    context.Response.ContentType = "application/json";
    await context.Response.WriteAsync(JsonSerializer.Serialize(envelope));

    Log.ForContext("method", method).ForContext("path", path)
       .ForContext("status_code", 502)
       .ForContext("duration_ms", (long)Stopwatch.GetElapsedTime(start).TotalMilliseconds)
       .Information("request completed");
}
