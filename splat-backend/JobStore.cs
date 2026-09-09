using System.Text.Json;

namespace BoboSplat;

public sealed class JobStore
{
    private readonly object gate = new();
    private readonly Dictionary<string, JobRecord> jobs = new();
    private readonly Dictionary<string, Queue<string>> tails = new();
    private readonly string root;
    public JobStore(BoboOptions options)
    {
        root = Path.GetFullPath(options.DataRoot);
        Directory.CreateDirectory(root);
        foreach (var dir in Directory.EnumerateDirectories(root))
        {
            var file = Path.Combine(dir, "job.json");
            if (!File.Exists(file)) continue;
            var record = JsonSerializer.Deserialize<JobRecord>(File.ReadAllText(file), JsonDefaults.Options)
                ?? throw new InvalidDataException($"无法读取任务状态：{file}");
            if (!Guid.TryParseExact(record.Id, "N", out _) || Path.GetFileName(dir) != record.Id)
                throw new InvalidDataException($"任务目录与 ID 不匹配：{file}");
            if (!record.IsTerminal) record = record with {
                Status = "interrupted", Error = "服务在任务完成前停止。请重新上传创建任务。", FinishedAt = DateTimeOffset.UtcNow
            };
            jobs[record.Id] = record;
            Save(record);
        }
    }
    public string DirectoryFor(string id)
    {
        if (!Guid.TryParseExact(id, "N", out _)) throw new ArgumentException("无效任务 ID。");
        return Path.Combine(root, id);
    }
    public JobRecord[] List() { lock (gate) return jobs.Values.OrderByDescending(x => x.CreatedAt).ToArray(); }
    public JobRecord? Get(string id) { lock (gate) return jobs.GetValueOrDefault(id); }
    public void Add(JobRecord record) { lock (gate) { Save(record); jobs.Add(record.Id, record); } }
    public void Update(string id, Func<JobRecord, JobRecord> update)
    {
        lock (gate) { var next = update(jobs[id]); Save(next); jobs[id] = next; }
    }
    private void Save(JobRecord record)
    {
        var dir = DirectoryFor(record.Id);
        Directory.CreateDirectory(dir);
        var path = Path.Combine(dir, "job.json");
        File.WriteAllText(path + ".tmp", JsonSerializer.Serialize(record, JsonDefaults.Options));
        File.Move(path + ".tmp", path, true);
    }
    public void Log(string id, string message)
    {
        if (message.Length > 4096) message = message[..4096];
        var line = $"{DateTimeOffset.Now:HH:mm:ss} {message}";
        lock (gate)
        {
            if (!tails.TryGetValue(id, out var tail)) tails[id] = tail = new();
            tail.Enqueue(line);
            while (tail.Count > 250) tail.Dequeue();
            var path = Path.Combine(DirectoryFor(id), "run.log");
            if (!File.Exists(path) || new FileInfo(path).Length < 16 * 1024 * 1024)
                File.AppendAllText(path, line + Environment.NewLine);
        }
    }
    public string[] Logs(string id)
    {
        lock (gate)
        {
            if (tails.TryGetValue(id, out var tail)) return tail.ToArray();
            var path = Path.Combine(DirectoryFor(id), "run.log");
            return File.Exists(path) ? File.ReadLines(path).TakeLast(250).ToArray() : Array.Empty<string>();
        }
    }
}
