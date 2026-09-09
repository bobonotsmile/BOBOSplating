using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace BoboSplat;

public sealed class Pipeline
{
    private readonly BoboOptions options;
    private readonly JobStore store;
    private readonly ProcessRunner runner;
    public Pipeline(BoboOptions options, JobStore store, ProcessRunner runner)
    { this.options = options; this.store = store; this.runner = runner; }

    public static double Duration(string json)
    {
        using var document = JsonDocument.Parse(json);
        var duration = double.Parse(document.RootElement.GetProperty("format").GetProperty("duration").GetString()!, CultureInfo.InvariantCulture);
        if (!double.IsFinite(duration) || duration <= 0 || duration > 3600)
            throw new InvalidDataException("视频时长必须大于 0 且不超过 60 分钟。");
        if (document.RootElement.GetProperty("streams").GetArrayLength() == 0)
            throw new InvalidDataException("文件不包含视频流。");
        return duration;
    }
    public static double Metric(string text, string name)
    {
        var match = Regex.Match(text, Regex.Escape(name) + @":\s*([0-9.]+)");
        if (!match.Success) throw new InvalidDataException($"COLMAP 未输出 {name}，无法确认重建质量。");
        return double.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture);
    }

    public async Task Execute(JobRecord job, CancellationToken ct)
    {
        var dir = store.DirectoryFor(job.Id);
        var quality = QualityProfile.Get(job.Profile);
        async Task<string> Run(string stage, string executable, params string[] args)
        {
            ct.ThrowIfCancellationRequested();
            store.Update(job.Id, x => x with { Stage = stage });
            store.Log(job.Id, $"开始阶段：{stage}");
            var lastStep = 0;
            return await runner.Run(executable, args, dir, line => {
                store.Log(job.Id, line);
                if (stage != "training") return;
                var progress = Regex.Match(line, @"(\d+)\s*/\s*" + quality.Steps + @"\b");
                if (progress.Success && int.TryParse(progress.Groups[1].Value, out var step) && step >= lastStep + 50)
                {
                    lastStep = step;
                    store.Update(job.Id, x => x with { Step = Math.Min(step, quality.Steps) });
                }
            }, ct);
        }
        var duration = Duration(await Run("probe", options.Tools.Ffprobe, "-v", "error", "-protocol_whitelist", "file,pipe", "-select_streams", "v:0",
            "-show_entries", "stream=width,height:format=duration", "-of", "json", job.InputFile));
        var fps = Math.Min(5, quality.Frames / duration).ToString("0.########", CultureInfo.InvariantCulture);
        Directory.CreateDirectory(Path.Combine(dir, "images"));
        await Run("frames", options.Tools.Ffmpeg, "-hide_banner", "-nostdin", "-n", "-protocol_whitelist", "file,pipe", "-i", job.InputFile,
            "-vf", $"fps={fps},scale=w='min({quality.Resolution},iw)':h='min({quality.Resolution},ih)':force_original_aspect_ratio=decrease",
            "-frames:v", quality.Frames.ToString(), "images/frame_%04d.png");
        var frames = Directory.GetFiles(Path.Combine(dir, "images"), "*.png").Length;
        if (frames < 10) throw new InvalidDataException("抽帧少于 10 张。请使用更长且视角连续的视频。");
        store.Update(job.Id, x => x with { Frames = frames });
        await Run("features", options.Tools.Colmap, "feature_extractor", "--database_path", "database.db", "--image_path", "images",
            "--ImageReader.single_camera", "1", "--ImageReader.camera_model", "SIMPLE_RADIAL", "--SiftExtraction.use_gpu", "0", "--SiftExtraction.num_threads", "4");
        await Run("matching", options.Tools.Colmap, "exhaustive_matcher", "--database_path", "database.db", "--SiftMatching.use_gpu", "0", "--SiftMatching.num_threads", "4");
        Directory.CreateDirectory(Path.Combine(dir, "sparse"));
        await Run("reconstruction", options.Tools.Colmap, "mapper", "--database_path", "database.db", "--image_path", "images", "--output_path", "sparse");
        string? best = null;
        double registered = 0, points = 0, error = 0;
        foreach (var model in Directory.GetDirectories(Path.Combine(dir, "sparse")))
        {
            if (!File.Exists(Path.Combine(model, "cameras.bin"))) continue;
            var report = await Run("validation", options.Tools.Colmap, "model_analyzer", "--path", model);
            var count = Metric(report, "Registered images");
            if (count <= registered) continue;
            registered = count; best = model; points = Metric(report, "Points"); error = Metric(report, "Mean reprojection error");
        }
        store.Update(job.Id, x => x with { RegisteredImages = (int)registered, Points = (long)points, ReprojectionError = error });
        if (best is null || points < 100 || registered < 10 || registered / frames < options.MinRegistrationRatio)
            throw new InvalidDataException($"重建未通过：最大模型注册 {registered}/{frames} 张，{points} 个点。请检查拍摄视差、模糊、移动物体或变焦。");
        Directory.CreateDirectory(Path.Combine(dir, "brush-data"));
        await Run("undistortion", options.Tools.Colmap, "image_undistorter", "--image_path", "images", "--input_path", best,
            "--output_path", "brush-data", "--output_type", "COLMAP");
        Directory.CreateDirectory(Path.Combine(dir, "output"));
        await Run("training", options.Tools.Brush, Path.Combine(dir, "brush-data"), "--total-steps", quality.Steps.ToString(),
            "--max-splats", quality.MaxSplats.ToString(), "--max-resolution", quality.Resolution.ToString(),
            "--growth-stop-iter", ((int)(quality.Steps * 0.7)).ToString(), "--export-every", "1000", "--export-path", Path.Combine(dir, "output"));
        var exported = Path.Combine(dir, "output", $"export_{quality.Steps}.ply");
        if (!File.Exists(exported) || new FileInfo(exported).Length < 100)
            throw new InvalidDataException("训练结束但未找到最终 PLY，未将任务标记为成功。");
        using (var reader = new StreamReader(exported))
        {
            if ((await reader.ReadLineAsync())?.Trim() != "ply") throw new InvalidDataException("输出不是有效的 PLY 文件。");
            var header = "";
            for (var i = 0; i < 100; i++) { var line = await reader.ReadLineAsync(); header += line + "\n"; if (line == "end_header") break; }
            if (!header.Contains("end_header") || !header.Contains("opacity") || !header.Contains("scale_0"))
                throw new InvalidDataException("PLY 缺少 Gaussian 属性。");
        }
        ct.ThrowIfCancellationRequested();
        File.Copy(exported, Path.Combine(dir, "scene.ply"), true);
        store.Update(job.Id, x => x with { ResultBytes = new FileInfo(exported).Length, Step = quality.Steps });
    }
}
