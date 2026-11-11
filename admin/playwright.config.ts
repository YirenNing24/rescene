import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "./tests",
  fullyParallel: false,
  workers: 1,
  timeout: 30000,
  use: {
    baseURL: process.env.ADMIN_TEST_ORIGIN ?? "http://127.0.0.1:8788",
    channel: "chrome",
    launchOptions: { args: ["--no-sandbox", "--disable-dev-shm-usage"] },
  },
  webServer: process.env.ADMIN_TEST_ORIGIN
    ? undefined
    : {
        command:
          "node node_modules/wrangler/bin/wrangler.js dev --port 8788 --ip 127.0.0.1 --local",
        url: "http://127.0.0.1:8788",
        reuseExistingServer: true,
      },
  reporter: "list",
});
