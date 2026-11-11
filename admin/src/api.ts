export type Row = Record<string, any>;
export async function api(
  path: string,
  body?: unknown,
  method?: string,
): Promise<Row> {
  const r = await fetch("/api/" + path, {
    method: method ?? (body === undefined ? "GET" : "POST"),
    headers: body === undefined ? {} : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
    credentials: "same-origin",
  });
  const v = await r
    .json()
    .catch(() => ({
      error: { message: "The gateway returned an unreadable response." },
    }));
  if (!r.ok)
    throw new Error(v.error?.message ?? `Request failed (${r.status})`);
  return v;
}
export const uid = () =>
  Array.from(crypto.getRandomValues(new Uint8Array(16)), (n) =>
    n.toString(16).padStart(2, "0"),
  ).join("");
export const pretty = (v: unknown) => JSON.stringify(v, null, 2);
export function date(v: any) {
  if (!v) return "—";
  const d = new Date(typeof v === "number" ? v : String(v));
  return Number.isNaN(+d)
    ? String(v)
    : d.toLocaleString(undefined, {
        month: "short",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      });
}
export function download(v: unknown, name: string) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(
    new Blob([pretty(v)], { type: "application/json" }),
  );
  a.download = name + ".json";
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}
export const photo = (url: string) => url?.replace("/api/v1/", "/api/");
