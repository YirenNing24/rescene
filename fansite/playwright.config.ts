import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  timeout: 30_000,
  use: {
    baseURL: process.env.SITE_TEST_URL || "http://127.0.0.1:4173",
    browserName: "chromium",
    channel: "chrome",
    viewport: { width: 1440, height: 1000 },
    launchOptions: { args: ["--no-sandbox", "--disable-dev-shm-usage"] },
  },
  webServer: process.env.SITE_TEST_URL
    ? undefined
    : {
        command:
          "wrangler dev --config wrangler.cloudflare.json --local --ip 127.0.0.1 --port 4173 --inspector-port 0",
        url: "http://127.0.0.1:4173",
        reuseExistingServer: false,
        timeout: 30_000,
      },
});
