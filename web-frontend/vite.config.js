import { defineConfig, loadEnv } from "vite";
import vue from "@vitejs/plugin-vue";
import { fileURLToPath } from "node:url";
import { licenses } from "./licenses.js";

const root = fileURLToPath(new URL("..", import.meta.url));
export default defineConfig(({ mode }) => {
  const env = { ...loadEnv(mode, root, ""), ...process.env };
  return {
    plugins: [vue(), licenses()],
    envDir: root,
    server: {
      host: "127.0.0.1",
      port: Number(env.BOBO_DEV_PORT || 9130),
      strictPort: true,
      proxy: {
        "^/api/": {
          target: env.BOBO_BACKEND_URL || "http://127.0.0.1:9131",
          changeOrigin: true,
        },
      },
    },
    build: { chunkSizeWarningLimit: 1800 },
  };
});
