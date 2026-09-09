import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "./e2e",
  timeout: 90000,
  workers: 1,
  use: {
    baseURL: process.env.BOBO_UI_TEST_URL || "http://127.0.0.1:9130",
    headless: true,
    channel: process.env.BOBO_BROWSER_CHANNEL || "msedge",
    viewport: { width: 1440, height: 1000 },
    launchOptions: { args: ["--enable-webgl", "--ignore-gpu-blocklist"] },
  },
  reporter: "list",
});
