import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "jsdom",
    include: ["test/javascript/**/*.test.js"],
    setupFiles: ["test/javascript/setup.js"],
    coverage: {
      provider: "v8",
      reporter: ["text", "json-summary", "html"],
      reportsDirectory: "tmp/js-coverage",
      include: ["app/javascript/storefront/**/*.js", "app/javascript/backoffice/**/*.js"],
      // Gate: storefront + backoffice modules must stay fully covered (browser
      // bootstrap is marked `/* v8 ignore */`). Fails the run (and CI) when it slips.
      thresholds: { lines: 100, functions: 100, branches: 100, statements: 100 },
    },
  },
});
