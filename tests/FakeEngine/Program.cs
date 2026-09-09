// Deterministic test double for orchestration tests; never used by production.
string Value(string flag) => args[Array.IndexOf(args, flag) + 1];
var input = Directory.GetFiles(Environment.CurrentDirectory, "input.*").FirstOrDefault();
var behavior = input is null ? "" : File.ReadAllText(input);
if (args.Contains("-show_entries"))
{
    if (behavior == "fail") { Console.Error.WriteLine("Invalid video fixture"); return 9; }
    if (behavior == "slow") await Task.Delay(TimeSpan.FromMinutes(5));
    Console.WriteLine("{\"streams\":[{\"width\":1280,\"height\":720}],\"format\":{\"duration\":\"13.1\"}}");
}
else if (args.Contains("-vf"))
{
    Directory.CreateDirectory("images");
    for (var i = 0; i < 66; i++) File.WriteAllText($"images/frame_{i:0000}.png", "fixture");
}
else if (args[0] == "mapper")
{
    Directory.CreateDirectory("sparse/0"); File.WriteAllText("sparse/0/cameras.bin", "fixture");
}
else if (args[0] == "model_analyzer")
{
    Console.Error.WriteLine($"Registered images: {(behavior == "low" ? 5 : 66)}\nPoints: 11552\nMean reprojection error: 0.733333px");
}
else if (args[0] == "image_undistorter")
{
    Directory.CreateDirectory(Value("--output_path"));
}
else if (args.Contains("--total-steps"))
{
    if (behavior != "missing")
    {
        var header = "ply\nformat ascii 1.0\nelement vertex 1\nproperty float x\nproperty float y\nproperty float z\nproperty float opacity\nproperty float scale_0\nproperty float scale_1\nproperty float scale_2\nend_header\n0 0 0 1 0 0 0\n";
        File.WriteAllText(Path.Combine(Value("--export-path"), "export_" + Value("--total-steps") + ".ply"), header);
    }
    Console.Write("\r365/5000 Steps\r5000/5000 Steps\nTraining took 1s\n");
}
return 0;
