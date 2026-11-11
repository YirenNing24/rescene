import fs from "node:fs";
import crypto from "node:crypto";
import { chromium } from "@playwright/test";
const base = process.env.ADMIN_TEST_ORIGIN ?? "http://127.0.0.1:8788";
const env = Object.fromEntries(
  fs
    .readFileSync("../backend/.env.admin", "utf8")
    .trim()
    .split("\n")
    .map((x) => {
      const i = x.indexOf("=");
      return [x.slice(0, i), x.slice(i + 1)];
    }),
);
const sign = (aud) => {
  const now = Math.floor(Date.now() / 1000);
  const h = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString(
      "base64url",
    ),
    p = Buffer.from(
      JSON.stringify({
        sub: env.ADMIN_OWNER_EMAIL,
        aud,
        exp: now + 300,
        iat: now,
      }),
    ).toString("base64url");
  return (
    h +
    "." +
    p +
    "." +
    crypto
      .createHmac("sha256", env.ADMIN_GATEWAY_SECRET)
      .update(h + "." + p)
      .digest("base64url")
  );
};
const browser = await chromium.launch({
  channel: "chrome",
  headless: true,
  args: ["--no-sandbox", "--disable-dev-shm-usage"],
});
const context = await browser.newContext({
  viewport: { width: 1440, height: 1080 },
});
let errors = [];
const page = await context.newPage();
page.on("pageerror", (e) => errors.push(e.message));
page.on("console", (m) => {
  if (m.type() === "error" && !m.text().includes("401")) errors.push(m.text());
});
await page.goto(base);
await page.getByRole("heading", { name: "Welcome backstage." }).waitFor();
console.log("Login page rendered");
const cookies = [
  ["__Host-remine_admin_auth", "remine-admin-gateway"],
  ["__Host-remine_admin_step", "remine-admin-step"],
].map(([name, aud]) => ({
  name,
  value: sign(aud),
  domain: new URL(base).hostname,
  path: "/",
  secure: true,
  httpOnly: true,
  sameSite: "Strict",
}));
await context.addCookies(cookies);
await page.reload();
await page
  .getByRole("heading", { name: "A clear view of your game." })
  .waitFor();
await page.locator(".metric>strong").first().waitFor();
await page.waitForFunction(
  () => document.querySelector(".metric>strong")?.textContent !== "—",
);
await page.screenshot({
  path: "../previews/admin-dashboard.png",
  fullPage: true,
});
console.log("Live dashboard rendered");
const names = [
  "Analytics",
  "Support inbox",
  "Missions & gifts",
  "Daily calendars",
  "Events",
  "Announcements",
  "Moderation",
  "Players",
  "Friends & profiles",
  "Runs & validation",
  "Songs & charts",
  "Leaderboards",
  "Store catalog",
  "Items & inventory",
  "Minting studio",
  "Card registry",
  "Refinement & skills",
  "Album decks",
  "Transactions",
  "Recovery queue",
  "Treasury & gas",
  "Player wallets",
  "Contracts",
  "PULSE launch",
  "Game controls",
  "Media library",
  "Team & access",
  "Audit log",
  "System health",
  "Releases & backups",
  "Version history",
];
for (const name of names) {
  await page
    .getByRole("navigation")
    .getByRole("button", { name, exact: true })
    .click();
  await page.waitForFunction(() => !document.querySelector(".loading"));
  const error = (await page.locator(".error-banner").isVisible())
    ? await page.locator(".error-banner").textContent()
    : null;
  console.log(name + ": " + (error ?? "OK"));
  if (error) errors.push(name + ": " + error);
}
await page
  .getByRole("navigation")
  .getByRole("button", { name: "Players", exact: true })
  .click();
await page.locator(".player-card").first().waitFor();
await page.locator(".player-card").first().click();
await page.getByRole("dialog", { name: "Player profile" }).waitFor();
await page.screenshot({
  path: "../previews/admin-player-profile.png",
  fullPage: true,
});
await page.getByRole("button", { name: "Friends", exact: true }).click();
await page.getByRole("button", { name: "Photos", exact: true }).click();
await page.getByRole("button", { name: "Close dialog" }).click();
await page
  .getByRole("navigation")
  .getByRole("button", { name: "Overview", exact: true })
  .click();
await page.waitForFunction(() => !document.querySelector(".loading"));
await page.setViewportSize({ width: 390, height: 844 });
await page.waitForFunction(()=>document.querySelector(".sidebar").getBoundingClientRect().right<=1);
await page.screenshot({ path: "../previews/admin-mobile.png", fullPage: true });
const overflow = await page.evaluate(
  () => document.documentElement.scrollWidth > innerWidth,
);
console.log("Mobile overflow:", overflow);
if (overflow) errors.push("Mobile overflow");
await browser.close();
if (errors.length) {
  console.error(JSON.stringify(errors, null, 2));
  process.exitCode = 1;
} else console.log("All checks passed. No browser errors.");
