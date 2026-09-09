export const stages = [
  ["probe", "读取视频"],
  ["frames", "抽取画面"],
  ["features", "提取特征"],
  ["matching", "匹配视角"],
  ["reconstruction", "恢复空间"],
  ["validation", "检查模型"],
  ["undistortion", "校正镜头"],
  ["training", "训练场景"],
];
export const statusNames = {
  queued: "等待处理",
  running: "正在重建",
  completed: "已完成",
  failed: "失败",
  cancelled: "已取消",
  interrupted: "已中断",
};
export function bytes(value) {
  if (!Number.isFinite(value)) return "—";
  if (value < 1048576) return `${(value / 1024).toFixed(0)} KB`;
  return `${(value / 1048576).toFixed(1)} MB`;
}
export function elapsed(job) {
  if (!job?.startedAt) return "—";
  const seconds = Math.max(
    0,
    Math.floor(
      ((job.finishedAt ? Date.parse(job.finishedAt) : Date.now()) -
        Date.parse(job.startedAt)) /
        1000,
    ),
  );
  return `${Math.floor(seconds / 60)} 分 ${seconds % 60} 秒`;
}
export function stageState(job, index) {
  if (!job) return "pending";
  if (job.status === "completed") return "done";
  const current = stages.findIndex(([id]) => id === job.stage);
  if (index < current) return "done";
  return index === current
    ? job.status === "running"
      ? "active"
      : "stopped"
    : "pending";
}
