using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;

namespace BoboSplat;

public sealed class ProcessRunner
{
    private readonly BoboOptions options;
    public ProcessRunner(BoboOptions options) => this.options = options;

    public async Task<string> Run(string executable, IEnumerable<string> arguments, string directory,
        Action<string> onLine, CancellationToken cancellationToken, int? timeoutSeconds = null)
    {
        var start = new ProcessStartInfo(executable) {
            WorkingDirectory = directory, UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true
        };
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        start.Environment["QT_QPA_PLATFORM"] = "offscreen";
        start.Environment["NO_COLOR"] = "1";
        using var process = new Process { StartInfo = start };
        try { process.Start(); }
        catch (Exception e) { throw new InvalidOperationException($"无法启动 {Path.GetFileName(executable)}，请检查工具路径及运行依赖：{e.Message}", e); }
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(timeoutSeconds ?? options.ProcessTimeoutMinutes * 60));
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeout.Token);
        using var registration = linked.Token.Register(() => {
            try { if (!process.HasExited) process.Kill(entireProcessTree: true); }
            catch (InvalidOperationException) { }
            catch (System.ComponentModel.Win32Exception) { }
        });
        var output = new StringBuilder();
        var gate = new object();
        void Line(string line)
        {
            line = Regex.Replace(line, @"\x1B\[[0-?]*[ -/]*[@-~]", "");
            if (string.IsNullOrWhiteSpace(line)) return;
            lock (gate)
            {
                if (output.Length < 2 * 1024 * 1024) output.AppendLine(line);
                onLine(line);
            }
        }
        var drains = Task.WhenAll(Drain(process.StandardOutput, Line), Drain(process.StandardError, Line));
        try
        {
            await process.WaitForExitAsync(linked.Token);
            await drains.WaitAsync(linked.Token);
            cancellationToken.ThrowIfCancellationRequested();
            if (process.ExitCode != 0)
                throw new InvalidOperationException($"{Path.GetFileName(executable)} 退出码 {process.ExitCode}。请查看当前阶段日志。");
            return output.ToString();
        }
        catch (OperationCanceledException)
        {
            try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
            await process.WaitForExitAsync();
            await drains;
            if (cancellationToken.IsCancellationRequested) throw;
            throw new TimeoutException($"{Path.GetFileName(executable)} 超时，已停止进程树。");
        }
    }
    private static async Task Drain(StreamReader reader, Action<string> onLine)
    {
        var buffer = new char[1024];
        var pending = new StringBuilder();
        int count;
        while ((count = await reader.ReadAsync(buffer, 0, buffer.Length)) > 0)
            for (var i = 0; i < count; i++)
            {
                if (buffer[i] is '\r' or '\n') { if (pending.Length > 0) onLine(pending.ToString()); pending.Clear(); }
                else if (pending.Length < 8192) pending.Append(buffer[i]);
            }
        if (pending.Length > 0) onLine(pending.ToString());
    }
}
