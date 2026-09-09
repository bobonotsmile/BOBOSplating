import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
export function licenses() {
  return {
    name: "third-party-licenses",
    generateBundle() {
      const names = [
        "vue",
        "@vue/shared",
        "@vue/reactivity",
        "@vue/runtime-core",
        "@vue/runtime-dom",
        "three",
        "@sparkjsdev/spark",
      ];
      const blocks = names.map((name) => {
        let dir = path.dirname(require.resolve(name));
        while (
          !fs.existsSync(path.join(dir, "package.json")) &&
          path.dirname(dir) !== dir
        )
          dir = path.dirname(dir);
        // Some entry points live in a dist folder with a local package.json.
        while (
          !fs.existsSync(path.join(dir, "LICENSE")) &&
          !fs.existsSync(path.join(dir, "LICENSE.md")) &&
          path.dirname(dir) !== dir
        )
          dir = path.dirname(dir);
        const file = ["LICENSE", "LICENSE.md"]
          .map((n) => path.join(dir, n))
          .find((p) => fs.existsSync(p));
        if (!file) throw new Error(`Missing license for ${name}`);
        return `=== ${name} ===\n${fs.readFileSync(file, "utf8")}`;
      });
      this.emitFile({
        type: "asset",
        fileName: "third-party-licenses.txt",
        source: blocks.join("\n\n"),
      });
    },
  };
}
