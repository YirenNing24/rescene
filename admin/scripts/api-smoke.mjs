import fs from "node:fs";
import crypto from "node:crypto";
const base = process.env.ADMIN_TEST_ORIGIN ?? "https://admin.remineph.online";
const cfg = Object.fromEntries(
  fs
    .readFileSync("../backend/.env.admin", "utf8")
    .trim()
    .split("\n")
    .map((x) => x.split("=")),
);
const sign = (aud) => {
  const h = Buffer.from('{"alg":"HS256"}').toString("base64url"),
    p = Buffer.from(
      JSON.stringify({
        sub: cfg.ADMIN_OWNER_EMAIL,
        aud,
        exp: Math.floor(Date.now() / 1000) + 300,
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
};
const cookie = `__Host-remine_admin_auth=${sign("remine-admin-gateway")}; __Host-remine_admin_step=${sign("remine-admin-step")}`;
const paths = [
  "rules",
  "data/analytics",
  "documents/missions",
  "documents/calendars",
  "documents/support",
  "documents/events",
  "documents/announcements",
  "documents/reports",
  "overview",
  "players",
  "data/social",
  "data/runs",
  "data/charts",
  "data/scores",
  "catalog",
  "data/items",
  "data/minting",
  "data/cards",
  "data/refinement",
  "data/decks",
  "data/transactions",
  "data/recovery",
  "chain",
  "data/wallets",
  "contracts",
  "data/launch",
  "documents/settings",
  "documents/assets",
  "identities",
  "data/audit",
  "data/health",
  "documents/releases",
  "data/history",
];
let failures = 0;
for (let i = 0; i < paths.length; i += 5)
  await Promise.all(
    paths.slice(i, i + 5).map(async (path) => {
      const r = await fetch(base + "/api/" + path, {
        headers: { Cookie: cookie },
      });
      const v = await r.json();
      console.log(
        path,
        r.status,
        v.error?.message ??
          (Array.isArray(v.rows) ? v.rows.length + " rows" : "OK"),
      );
      if (!r.ok) failures++;
    }),
  );
process.exitCode = failures ? 1 : 0;
