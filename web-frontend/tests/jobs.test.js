import test from "node:test";
import assert from "node:assert/strict";
import { bytes, elapsed, stageState } from "../jobs.js";
test("阶段失败不能显示为成功", () => {
  const job = { status: "failed", stage: "matching" };
  assert.equal(stageState(job, 2), "done");
  assert.equal(stageState(job, 3), "stopped");
  assert.equal(stageState(job, 4), "pending");
});
test("排队任务不虚构进度，完成任务标记全部阶段", () => {
  assert.equal(stageState({ status: "queued", stage: "queued" }, 0), "pending");
  assert.equal(stageState({ status: "completed" }, 7), "done");
});
test("文件大小和结束时间格式", () => {
  assert.equal(bytes(6291456), "6.0 MB");
  assert.equal(bytes(undefined), "—");
  assert.equal(
    elapsed({
      startedAt: "2026-09-08T00:00:00Z",
      finishedAt: "2026-09-08T00:01:47Z",
    }),
    "1 分 47 秒",
  );
});
