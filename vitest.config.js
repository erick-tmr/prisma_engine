import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "jsdom",
    include: ["test/javascript/**/*.test.js"],
    coverage: {
      provider: "v8",
      reporter: ["text", "html"],
      reportsDirectory: "tmp/js-coverage",
      include: ["app/javascript/storefront/**/*.js"],
    },
  },
});
