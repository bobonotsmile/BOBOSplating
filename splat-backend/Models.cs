using System.Text.Json;

namespace BoboSplat;

public sealed class BoboOptions
{
    public string DataRoot { get; set; } = "./data";
    public long MaxUploadBytes { get; set; } = 1_073_741_824;
    public int MaxPendingJobs { get; set; } = 20;
    public int ProcessTimeoutMinutes { get; set; } = 120;
    public double MinRegistrationRatio { get; set; } = 0.8;
    public ToolPaths Tools { get; set; } = new();
}

public sealed class ToolPaths
{
    public string Ffmpeg { get; set; } = "ffmpeg";
    public string Ffprobe { get; set; } = "ffprobe";
    public string Colmap { get; set; } = "colmap";
    public string Brush { get; set; } = "brush_app";
}

public sealed record QualityProfile(string Id, string Name, int Frames, int Steps, int MaxSplats, int Resolution)
{
    public static readonly QualityProfile[] All = {
        new("quick", "快速预览", 80, 5000, 500000, 1280),
        new("balanced", "均衡重建", 160, 15000, 1000000, 1600)
    };
    public static QualityProfile Get(string id) => All.FirstOrDefault(p => p.Id == id)
        ?? throw new ArgumentException("未知质量档位。请选择 quick 或 balanced。");
}

public sealed record JobRecord
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    public string Profile { get; init; } = "quick";
    public string InputFile { get; init; } = "";
    public string Status { get; init; } = "queued";
    public string Stage { get; init; } = "queued";
    public int? Step { get; init; }
    public int TotalSteps { get; init; }
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? StartedAt { get; init; }
    public DateTimeOffset? FinishedAt { get; init; }
    public string? Error { get; init; }
    public int? Frames { get; init; }
    public int? RegisteredImages { get; init; }
    public long? Points { get; init; }
    public double? ReprojectionError { get; init; }
    public long? ResultBytes { get; init; }
    public bool IsTerminal => Status is "completed" or "failed" or "cancelled" or "interrupted";
}

public static class JsonDefaults
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web) { WriteIndented = true };
}
