namespace BoboSplat;

public static class ToolAvailability
{
    public static string[] Missing(BoboOptions options)
    {
        var tools = new Dictionary<string, string> {
            ["FFmpeg"] = options.Tools.Ffmpeg, ["FFprobe"] = options.Tools.Ffprobe,
            ["COLMAP"] = options.Tools.Colmap, ["Brush"] = options.Tools.Brush
        };
        return tools.Where(pair => !Exists(pair.Value)).Select(pair => pair.Key).ToArray();
    }
    private static bool Exists(string name)
    {
        if (string.IsNullOrWhiteSpace(name)) return false;
        if (Path.IsPathRooted(name) || name.Contains(Path.DirectorySeparatorChar) || name.Contains(Path.AltDirectorySeparatorChar))
            return File.Exists(Path.GetFullPath(name));
        var extensions = OperatingSystem.IsWindows() ? new[] { "", ".exe" } : new[] { "" };
        return (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator)
            .Where(path => !string.IsNullOrWhiteSpace(path))
            .Any(path => extensions.Any(ext => File.Exists(Path.Combine(path.Trim('"'), name + ext))));
    }
}
