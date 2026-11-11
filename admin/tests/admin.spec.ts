import { test, expect } from "@playwright/test";
import fs from "node:fs";
import crypto from "node:crypto";
const cfg = Object.fromEntries(
  fs
    .readFileSync("../backend/.env.admin", "utf8")
    .trim()
    .split("\n")
    .map((x) => {
      const i = x.indexOf("=");
      return [x.slice(0, i), x.slice(i + 1)];
    }),
);
function sign(aud: string) {
  const h = Buffer.from('{"alg":"HS256"}').toString("base64url"),
    p = Buffer.from(
      JSON.stringify({
        sub: cfg.ADMIN_OWNER_EMAIL,
        aud,
        exp: Math.floor(Date.now() / 1000) + 180,
      }),
    ).toString("base64url");
  return (
    h +
    "." +
    p +
    "." +
    crypto
      .createHmac("sha256", cfg.ADMIN_GATEWAY_SECRET)
      .update(h + "." + p)
      .digest("base64url")
  );
}
test("public shell protects data and rejects cross-origin writes", async ({
  page,
  request,
  baseURL,
}) => {
  await page.goto("/");
  await expect(
    page.getByRole("heading", { name: "Welcome backstage." }),
  ).toBeVisible();
  const r = await request.get("/api/overview");
  expect(r.status()).toBe(401);
  const csrf = await request.post("/api/login", {
    data: { email: cfg.ADMIN_OWNER_EMAIL, key: "invalid" },
    headers: { Origin: "https://untrusted.invalid" },
  });
  expect(csrf.status()).toBe(403);
  const login = await request.post("/api/login", {
    data: { email: cfg.ADMIN_OWNER_EMAIL, key: cfg.ADMIN_BOOTSTRAP_KEY },
    headers: { Origin: baseURL! },
  });
  expect(login.status()).toBe(200);
  const overview = await request.get("/api/overview");
  expect(overview.status()).toBe(428);
});
test("live overview, profiles, mint review and responsive layout", async ({
  page,
  context,
  baseURL,
}) => {
  const hostname = new URL(baseURL!).hostname;
  await context.addCookies(
    [
      ["__Host-remine_admin_auth", "remine-admin-gateway"],
      ["__Host-remine_admin_step", "remine-admin-step"],
    ].map(([name, aud]) => ({
      name,
      value: sign(aud),
      domain: hostname,
      path: "/",
      secure: true,
      httpOnly: true,
      sameSite: "Strict",
    })),
  );
  await page.goto("/");
  await expect(
    page.getByRole("heading", { name: "A clear view of your game." }),
  ).toBeVisible();
  await expect(page.locator(".metric>strong").first()).not.toHaveText("—");
  await page
    .getByRole("button", { name: "Create operation", exact: true })
    .click();
  await expect(page.getByRole("dialog")).toBeVisible();
  await expect(page.getByLabel("Recipient wallet")).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Save intent for review" }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Close dialog" }).click();
  await page
    .getByRole("navigation")
    .getByRole("button", { name: "Players", exact: true })
    .click();
  await page.locator(".player-card").first().click();
  await expect(
    page.getByRole("dialog", { name: "Player profile" }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Friends", exact: true }).click();
  await expect(
    page.getByText("Mutual follows are friends.", { exact: false }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Photos", exact: true }).click();
  await expect(
    page.getByText("Players can use an avatar", { exact: false }),
  ).toBeVisible();
  await page.getByRole("button",{name:"Support",exact:true}).click();
  await page.getByRole("button",{name:"Suspend account",exact:true}).click();
  await expect(page.getByRole("dialog")).toHaveCount(1);
  await expect(page.getByLabel("Player ID",{exact:true})).not.toHaveValue("");
  await page.getByRole("button", { name: "Close dialog" }).click();
  await page.setViewportSize({ width: 390, height: 844 });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
});
