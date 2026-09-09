using System.Diagnostics;
using System.Net;
using System.Net.Http.Json;
using System.Net.Sockets;
using BoboSplat;

var checks = 0;
void Check(bool ok, string name) { if (!ok) throw new Exception("FAIL: " + name); Console.WriteLine("PASS: " + name); checks++; }
void Throws(Action action, string name) { try { action(); } catch { Check(true, name); return; } throw new Exception("FAIL: " + name); }
Throws(() => Pipeline.Duration("{\"streams\":[{}],\"format\":{\"duration\":\"0\"}}"), "reject zero duration");
Throws(() => Pipeline.Duration("{\"streams\":[],\"format\":{\"duration\":\"12\"}}"), "reject non-video input");
Throws(() => QualityProfile.Get("anything"), "reject unknown quality profile");
Check(ToolAvailability.Missing(new BoboOptions { Tools = new ToolPaths { Brush = "__bobo_nonexistent_engine__" } }).Contains("Brush"), "detect missing training executable");
Check(Pipeline.Metric("I123 Mean reprojection error: 0.733333px", "Mean reprojection error") == .733333, "parse COLMAP log prefix and px suffix");
var project = Path.GetFullPath(args.FirstOrDefault() ?? Environment.CurrentDirectory);
var temporary = Path.Combine(Path.GetTempPath(), "bobosplating-tests-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(temporary);
var recoveryRoot = Path.Combine(temporary, "recovery");
var original = new JobStore(new BoboOptions { DataRoot = recoveryRoot });
var interruptedId = Guid.NewGuid().ToString("N");
original.Add(new JobRecord { Id = interruptedId, Status = "running" });
var recovered = new JobStore(new BoboOptions { DataRoot = recoveryRoot });
Check(recovered.Get(interruptedId)?.Status == "interrupted", "restart marks unfinished jobs interrupted");
Throws(() => recovered.DirectoryFor("../../outside"), "reject path traversal IDs");
var socket = new TcpListener(IPAddress.Loopback, 0); socket.Start(); var port = ((IPEndPoint)socket.LocalEndpoint).Port; socket.Stop();
var backend = Path.Combine(project, "splat-backend/bin/Release/net6.0/BoboSplat.Api.dll");
var engine = Path.Combine(project, "tests/FakeEngine/bin/Release/net6.0/FakeEngine" + (OperatingSystem.IsWindows() ? ".exe" : ""));
var start = new ProcessStartInfo("dotnet") { WorkingDirectory = project, UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true, RedirectStandardOutput = true };
start.ArgumentList.Add(backend);
start.Environment["ASPNETCORE_URLS"] = $"http://127.0.0.1:{port}";
start.Environment["Bobo__DataRoot"] = Path.Combine(temporary, "http");
start.Environment["Bobo__MaxUploadBytes"] = "2048";
foreach (var tool in new[] { "Ffmpeg", "Ffprobe", "Colmap", "Brush" }) start.Environment["Bobo__Tools__" + tool] = engine;
using var process = Process.Start(start)!;
var stdout = process.StandardOutput.ReadToEndAsync(); var stderr = process.StandardError.ReadToEndAsync();
try
{
    using var client = new HttpClient { BaseAddress = new Uri($"http://127.0.0.1:{port}"), Timeout = TimeSpan.FromSeconds(20) };
    var ready = false;
    for (var i = 0; i < 80; i++)
    {
        try { ready = (await client.GetAsync("/api/health")).IsSuccessStatusCode; if (ready) break; } catch (HttpRequestException) { }
        await Task.Delay(100);
    }
    Check(ready, "real HTTP health endpoint");
    Check((await client.PostAsync("/api/jobs", new StringContent("x"))).StatusCode == HttpStatusCode.Forbidden, "reject cross-site form without custom header");
    client.DefaultRequestHeaders.Add("X-Bobo-Client", "web");
    async Task<HttpResponseMessage> Upload(string contents, string filename = "test.mp4", string profile = "quick")
    {
        using var form = new MultipartFormDataContent(); form.Add(new StringContent(profile), "profile");
        form.Add(new ByteArrayContent(System.Text.Encoding.UTF8.GetBytes(contents)), "video", filename);
        return await client.PostAsync("/api/jobs", form);
    }
    async Task<JobRecord> Submit(string behavior)
    {
        using var response = await Upload(behavior);
        Check(response.StatusCode == HttpStatusCode.Accepted, "accept " + behavior + " job");
        return (await response.Content.ReadFromJsonAsync<JobRecord>())!;
    }
    async Task<JobRecord> Wait(string id)
    {
        for (var i = 0; i < 150; i++) { var job = (await client.GetFromJsonAsync<JobRecord>("/api/jobs/" + id))!; if (job.IsTerminal) return job; await Task.Delay(100); }
        throw new Exception("Job wait timeout");
    }
    Check((await Upload("x", "bad.exe")).StatusCode == HttpStatusCode.BadRequest, "reject unsupported extension");
    Check((await Upload("x", "test.mp4", "bad")).StatusCode == HttpStatusCode.BadRequest, "reject invalid profile over HTTP");
    Check((await Upload(new string('x', 2049))).StatusCode == HttpStatusCode.RequestEntityTooLarge, "enforce video size limit");
    var success = await Wait((await Submit("ok")).Id);
    Check(success.Status == "completed" && success.RegisteredImages == 66 && success.ResultBytes > 100, "full pipeline orchestration and quality report");
    using var rangeRequest = new HttpRequestMessage(HttpMethod.Get, $"/api/jobs/{success.Id}/scene.ply");
    rangeRequest.Headers.Range = new System.Net.Http.Headers.RangeHeaderValue(0, 2);
    using var range = await client.SendAsync(rangeRequest);
    Check(range.StatusCode == HttpStatusCode.PartialContent && await range.Content.ReadAsStringAsync() == "ply", "PLY download supports range requests");
    Check((await client.GetFromJsonAsync<string[]>($"/api/jobs/{success.Id}/logs"))!.Any(x => x.Contains("5000/5000")), "capture carriage-return training progress");
    var failed = await Wait((await Submit("fail")).Id);
    Check(failed.Status == "failed" && failed.Stage == "probe", "failed process stops downstream stages");
    var low = await Wait((await Submit("low")).Id);
    Check(low.Status == "failed" && low.Stage == "validation", "reject low registration before training");
    var missing = await Wait((await Submit("missing")).Id);
    Check(missing.Status == "failed" && missing.ResultBytes is null, "missing final PLY cannot report success");
    var slow = await Submit("slow");
    await Task.Delay(400);
    var queued = await Submit("ok");
    Check((await client.GetFromJsonAsync<JobRecord>("/api/jobs/" + queued.Id))!.Status == "queued", "single active worker serializes jobs");
    Check((await client.PostAsync($"/api/jobs/{slow.Id}/cancel", null)).StatusCode == HttpStatusCode.Accepted, "accept cancellation");
    Check((await Wait(slow.Id)).Status == "cancelled", "cancel running native process");
    Check((await Wait(queued.Id)).Status == "completed", "queue continues after cancellation");
    Check((await client.PostAsync($"/api/jobs/{success.Id}/cancel", null)).StatusCode == HttpStatusCode.Conflict, "cannot cancel completed job");
    Console.WriteLine($"All {checks} checks passed. Native engines were test doubles; GPU quality is not asserted.");
}
finally
{
    if (!process.HasExited) process.Kill(entireProcessTree: true);
    await process.WaitForExitAsync();
    var diagnostics = await stdout + await stderr;
    Console.WriteLine("Test artifacts: " + temporary);
    File.WriteAllText(Path.Combine(temporary, "server.log"), diagnostics);
}
