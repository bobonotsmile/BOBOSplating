import { test, expect } from "@playwright/test";
test("工作台和已有 PLY 加载；无需后端即可预览", async ({ page }) => {
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toContainText("让画面");
  await expect(page.getByRole("button", { name: /开始重建/ })).toBeDisabled();
  const ply = process.env.BOBO_TEST_PLY;
  if (ply) {
    await page.locator('input[accept=".ply"]').setInputFiles(ply);
    await expect(page.locator(".viewer-toolbar")).toBeVisible({
      timeout: 60000,
    });
    await expect(page.locator(".viewer-toolbar")).toContainText("Gaussians");
    await page.getByRole("button", { name: "重置视角" }).click();
    await page.getByRole("button", { name: "上下翻转" }).click();
    const canvas = page.locator(".viewer-canvas canvas");
    await expect(canvas).toBeVisible();
    const box = await canvas.boundingBox();
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
    await page.mouse.move(
      box.x + box.width / 2 + 80,
      box.y + box.height / 2 + 25,
      { steps: 10 },
    );
    await page.mouse.up();
    await page.waitForTimeout(1500);
  }
  await page.screenshot({ path: "test-results/workbench.png", fullPage: true });
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
  expect(errors).toEqual([]);
});
