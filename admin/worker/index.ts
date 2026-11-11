interface Env {
  ASSETS: Fetcher;
  ADMIN_GATEWAY_SECRET: string;
  API_ORIGIN: string;
}
const encoder = new TextEncoder();
const hex = (b: ArrayBuffer) =>
  [...new Uint8Array(b)].map((n) => n.toString(16).padStart(2, "0")).join("");
const bytes = (s: string) =>
  Uint8Array.from(atob(s.replaceAll("-", "+").replaceAll("_", "/")), (c) =>
    c.charCodeAt(0),
  );
async function key(secret: string) {
  return crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}
async function identity(request: Request, env: Env) {
  try {
    const cookie = request.headers.get("cookie") ?? "";
    const jwt = cookie.match(/(?:^|;\s*)__Host-remine_admin_auth=([^;]+)/)?.[1];
    if (!jwt) return null;
    const [header, payload, sig, ...extra] = jwt.split(".");
    if (
      extra.length ||
      JSON.parse(new TextDecoder().decode(bytes(header))).alg !== "HS256"
    )
      return null;
    const valid = await crypto.subtle.verify(
      "HMAC",
      await key(env.ADMIN_GATEWAY_SECRET),
      bytes(sig),
      encoder.encode(header + "." + payload),
    );
    if (!valid) return null;
    const claims = JSON.parse(new TextDecoder().decode(bytes(payload)));
    if (
      typeof claims.exp !== "number" ||
      claims.aud !== "remine-admin-gateway" ||
      claims.exp < Date.now() / 1000 ||
      claims.iat > Date.now() / 1000 + 30 ||
      typeof claims.sub !== "string"
    )
      return null;
    return claims.sub.toLowerCase();
  } catch {
    return null;
  }
}
function json(status: number, code: string, message: string) {
  return Response.json(
    { error: { code, message } },
    { status, headers: { "Cache-Control": "no-store" } },
  );
}
function secured(response: Response) {
  const r = new Response(response.body, response);
  if (r.headers.get("Content-Type")?.includes("text/html"))
    r.headers.set(
      "Cache-Control",
      "public, max-age=0, must-revalidate, no-transform",
    );
  r.headers.set("X-Content-Type-Options", "nosniff");
  r.headers.set("X-Frame-Options", "DENY");
  r.headers.set("Referrer-Policy", "same-origin");
  r.headers.set("Permissions-Policy", "camera=(),microphone=(),geolocation=()");
  r.headers.set(
    "Content-Security-Policy",
    "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data: blob:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'",
  );
  r.headers.set(
    "Strict-Transport-Security",
    "max-age=31536000; includeSubDomains",
  );
  return r;
}
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    // Origin routing is deployment configuration; retired desktop tunnels cannot override it.
    if (url.pathname.startsWith("/internal/"))
      return secured(json(404, "not_found", "Endpoint not found."));
    if (!url.pathname.startsWith("/api/")) {
      return secured(await env.ASSETS.fetch(request));
    }
    if (!env.ADMIN_GATEWAY_SECRET || !env.API_ORIGIN)
      return secured(
        json(
          503,
          "not_configured",
          "The private API connection is not configured.",
        ),
      );
    if (
      request.method !== "GET" &&
      request.headers.get("Origin") !== url.origin
    )
      return secured(
        json(
          403,
          "origin_required",
          "This action must originate from the administration app.",
        ),
      );
    if (!["GET", "POST"].includes(request.method))
      return secured(
        json(405, "method_not_allowed", "Unsupported request method."),
      );
    const max = url.pathname === "/api/assets" ? 8388608 : 65536;
    if (Number(request.headers.get("content-length") ?? 0) > max)
      return secured(json(413, "body_limit", "Request is too large."));
    const body =
      request.method === "GET"
        ? new ArrayBuffer(0)
        : await request.arrayBuffer();
    if (body.byteLength > max)
      return secured(json(413, "body_limit", "Request is too large."));
    let email = await identity(request, env);
    if (url.pathname === "/api/login") {
      try {
        const b = JSON.parse(new TextDecoder().decode(body));
        email =
          typeof b.email === "string" ? b.email.trim().toLowerCase() : null;
      } catch {
        return secured(
          json(400, "invalid_request", "Send a valid login request."),
        );
      }
    }
    if (!email)
      return secured(
        json(
          401,
          "authentication_required",
          "Sign in to the administrator workspace.",
        ),
      );
    const target = new URL(env.API_ORIGIN);
    target.pathname = "/api/admin/v1/" + url.pathname.slice(5);
    target.search = url.search;
    const timestamp = Math.floor(Date.now() / 1000).toString(),
      nonce = crypto.randomUUID();
    const digest = hex(await crypto.subtle.digest("SHA-256", body));
    const signed = [
      request.method,
      target.pathname + target.search,
      email,
      timestamp,
      nonce,
      digest,
    ].join("\n");
    const headers = new Headers({
      "X-Admin-Email": email,
      "X-Admin-Time": timestamp,
      "X-Admin-Nonce": nonce,
      "X-Admin-Signature": hex(
        await crypto.subtle.sign(
          "HMAC",
          await key(env.ADMIN_GATEWAY_SECRET),
          encoder.encode(signed),
        ),
      ),
      "X-Admin-IP": request.headers.get("CF-Connecting-IP") ?? "local",
      "Content-Type": request.headers.get("Content-Type") ?? "application/json",
    });
    const cookies = (request.headers.get("Cookie") ?? "")
      .split(";")
      .map((x) => x.trim())
      .filter((x) => x.startsWith("__Host-remine_admin_step="))
      .join("; ");
    if (cookies) headers.set("Cookie", cookies);
    try {
      const result = await fetch(target, {
        method: request.method,
        headers,
        body: request.method === "GET" ? undefined : body,
        redirect: "manual",
        signal: AbortSignal.timeout(24000),
      });
      if (
        !result.ok &&
        !result.headers.get("Content-Type")?.includes("application/json")
      )
        return secured(
          json(
            503,
            "origin_unavailable",
            "The private game API connection is temporarily unavailable.",
          ),
        );
      const r = new Response(result.body, {
        status: result.status,
        headers: result.headers,
      });
      r.headers.set("Cache-Control", "no-store");
      return secured(r);
    } catch {
      return secured(
        json(
          503,
          "origin_unavailable",
          "The game API is temporarily unreachable. Please retry.",
        ),
      );
    }
  },
};
