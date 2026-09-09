using BoboSplat;
using Microsoft.AspNetCore.Http.Features;

var builder = WebApplication.CreateBuilder(args);
// Configuration is process environment / command line, never a checked-in secret file.
((IConfigurationBuilder)builder.Configuration).Sources.Clear();
builder.Configuration.AddEnvironmentVariables().AddCommandLine(args);
builder.WebHost.UseUrls(builder.Configuration["urls"] ?? Environment.GetEnvironmentVariable("ASPNETCORE_URLS") ?? "http://127.0.0.1:9131");
var options = new BoboOptions();
builder.Configuration.GetSection("Bobo").Bind(options);
if (options.MaxUploadBytes < 1024 || options.MaxPendingJobs is < 1 or > 1000 || options.ProcessTimeoutMinutes is < 1 or > 1440
    || options.MinRegistrationRatio is < 0.1 or > 1) throw new InvalidOperationException("Bobo 配置超出有效范围。");
// Resolve relative data paths against the project root for direct source runs.
builder.Services.Configure<FormOptions>(x => x.MultipartBodyLengthLimit = options.MaxUploadBytes + 1024 * 1024);
builder.WebHost.ConfigureKestrel(x => x.Limits.MaxRequestBodySize = options.MaxUploadBytes + 1024 * 1024);
builder.Services.AddSingleton(options);
builder.Services.AddSingleton<JobStore>();
builder.Services.AddSingleton<ProcessRunner>();
builder.Services.AddSingleton<Pipeline>();
builder.Services.AddSingleton<JobQueue>();
builder.Services.AddHostedService(x => x.GetRequiredService<JobQueue>());
var app = builder.Build();
app.Use(async (context, next) => {
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    // A custom header plus no CORS prevents cross-site forms from creating/cancelling jobs.
    if (context.Request.Method == "POST" && context.Request.Headers["X-Bobo-Client"] != "web")
    { context.Response.StatusCode = 403; await context.Response.WriteAsJsonAsync(new { error = "缺少 X-Bobo-Client 请求头。" }); return; }
    try { await next(); }
    catch (BadHttpRequestException e) { context.Response.StatusCode = e.StatusCode; await context.Response.WriteAsJsonAsync(new { error = "请求过大或格式无效。" }); }
    catch (InvalidDataException e) { context.Response.StatusCode = 400; await context.Response.WriteAsJsonAsync(new { error = e.Message }); }
    catch (ArgumentException e) { context.Response.StatusCode = 400; await context.Response.WriteAsJsonAsync(new { error = e.Message }); }
});
app.MapGet("/api/health", () => Results.Ok(new { status = "ok", name = "BOBOSplating", version = "0.1.0" }));
app.MapGet("/api/settings", () => {
    var missingTools = ToolAvailability.Missing(options);
    return Results.Ok(new { profiles = QualityProfile.All, maxUploadBytes = options.MaxUploadBytes, toolsReady = missingTools.Length == 0, missingTools });
});
app.MapGet("/api/jobs", (JobStore store) => store.List());
app.MapGet("/api/jobs/{id}", (string id, JobStore store) => store.Get(id) is { } job ? Results.Ok(job) : Results.NotFound());
app.MapGet("/api/jobs/{id}/logs", (string id, JobStore store) => store.Get(id) is not null ? Results.Ok(store.Logs(id)) : Results.NotFound());
app.MapGet("/api/jobs/{id}/scene.ply", (string id, JobStore store) => {
    if (store.Get(id)?.Status != "completed") return Results.NotFound();
    var path = Path.Combine(store.DirectoryFor(id), "scene.ply");
    return File.Exists(path) ? Results.File(path, "application/octet-stream", "scene.ply", enableRangeProcessing: true) : Results.NotFound();
});
app.MapPost("/api/jobs/{id}/cancel", (string id, JobStore store, JobQueue queue) => {
    var job = store.Get(id);
    if (job is null) return Results.NotFound();
    if (job.IsTerminal) return Results.Conflict(new { error = "任务已经结束。" });
    return queue.Cancel(id) ? Results.Accepted() : Results.Conflict(new { error = "任务当前无法取消。" });
});
app.MapPost("/api/jobs", async (HttpRequest request, JobStore store, JobQueue queue, CancellationToken ct) => {
    var missingTools = ToolAvailability.Missing(options);
    if (missingTools.Length > 0) return Results.Json(new { error = "计算工具尚未配置：" + string.Join("、", missingTools) }, statusCode: 503);
    if (!request.HasFormContentType) return Results.BadRequest(new { error = "请以 multipart/form-data 上传视频。" });
    var form = await request.ReadFormAsync(ct);
    var profile = QualityProfile.Get(form["profile"].FirstOrDefault() ?? "quick");
    var file = form.Files.GetFile("video");
    if (file is null || file.Length == 0) return Results.BadRequest(new { error = "请选择视频文件。" });
    if (file.Length > options.MaxUploadBytes) return Results.StatusCode(413);
    var extension = Path.GetExtension(file.FileName).ToLowerInvariant();
    if (extension is not (".mp4" or ".mov" or ".mkv" or ".webm")) return Results.BadRequest(new { error = "支持 MP4、MOV、MKV、WebM 视频。" });
    if (store.List().Count(x => !x.IsTerminal) >= options.MaxPendingJobs) return Results.Conflict(new { error = "任务队列已满，请稍后重试。" });
    var id = Guid.NewGuid().ToString("N");
    var dir = store.DirectoryFor(id);
    Directory.CreateDirectory(dir);
    var input = "input" + extension;
    var path = Path.Combine(dir, input);
    try { await using var output = new FileStream(path, FileMode.CreateNew); await file.CopyToAsync(output, ct); }
    catch { File.Delete(path); Directory.Delete(dir); throw; }
    var name = Path.GetFileName(file.FileName.Replace('\\', '/'));
    if (name.Length > 160) name = name[..160];
    var job = new JobRecord { Id = id, Name = name, Profile = profile.Id, InputFile = input, TotalSteps = profile.Steps };
    store.Add(job);
    if (!queue.Enqueue(id))
    {
        store.Update(id, x => x with { Status = "failed", Error = "队列已满。", FinishedAt = DateTimeOffset.UtcNow });
        return Results.Conflict(new { error = "队列已满，请稍后重试。" });
    }
    return Results.Accepted($"/api/jobs/{id}", store.Get(id));
});
app.Run();
