using System.Collections.Concurrent;
using System.Threading.Channels;

namespace BoboSplat;

public sealed class JobQueue : BackgroundService
{
    private readonly Channel<string> queue;
    private readonly ConcurrentDictionary<string, CancellationTokenSource> cancellation = new();
    private readonly JobStore store;
    private readonly Pipeline pipeline;
    private readonly ILogger<JobQueue> logger;
    public JobQueue(BoboOptions options, JobStore store, Pipeline pipeline, ILogger<JobQueue> logger)
    {
        queue = Channel.CreateBounded<string>(new BoundedChannelOptions(options.MaxPendingJobs) { SingleReader = true, FullMode = BoundedChannelFullMode.Wait });
        this.store = store; this.pipeline = pipeline; this.logger = logger;
    }
    public bool Enqueue(string id)
    {
        var cts = new CancellationTokenSource();
        if (!cancellation.TryAdd(id, cts)) { cts.Dispose(); return false; }
        if (queue.Writer.TryWrite(id)) return true;
        cancellation.TryRemove(id, out _); cts.Dispose(); return false;
    }
    public bool Cancel(string id)
    {
        if (!cancellation.TryGetValue(id, out var cts)) return false;
        try { cts.Cancel(); } catch (ObjectDisposedException) { return false; }
        return true;
    }
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try
        {
            await foreach (var id in queue.Reader.ReadAllAsync(stoppingToken))
            {
                if (!cancellation.TryGetValue(id, out var cts)) continue;
                using var linked = CancellationTokenSource.CreateLinkedTokenSource(cts.Token, stoppingToken);
                try
                {
                    linked.Token.ThrowIfCancellationRequested();
                    store.Update(id, x => x with { Status = "running", StartedAt = DateTimeOffset.UtcNow });
                    await pipeline.Execute(store.Get(id)!, linked.Token);
                    linked.Token.ThrowIfCancellationRequested();
                    store.Update(id, x => x with { Status = "completed", Stage = "completed", FinishedAt = DateTimeOffset.UtcNow });
                    store.Log(id, "任务完成，scene.ply 已就绪。");
                }
                catch (OperationCanceledException)
                {
                    store.Update(id, x => x with { Status = stoppingToken.IsCancellationRequested ? "interrupted" : "cancelled", FinishedAt = DateTimeOffset.UtcNow });
                    store.Log(id, "任务已停止。");
                }
                catch (Exception e)
                {
                    logger.LogError(e, "Job {JobId} failed", id);
                    store.Update(id, x => x with { Status = "failed", Error = e.Message, FinishedAt = DateTimeOffset.UtcNow });
                    store.Log(id, e.Message);
                }
                finally { cancellation.TryRemove(id, out _); cts.Dispose(); }
            }
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { }
        finally
        {
            foreach (var pair in cancellation)
            {
                store.Update(pair.Key, x => x with { Status = "interrupted", FinishedAt = DateTimeOffset.UtcNow });
                pair.Value.Dispose();
            }
            cancellation.Clear();
        }
    }
}
