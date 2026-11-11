import { writeFile, readFile, readdir } from "node:fs/promises";
import { gzipSync } from "node:zlib";
import { handleRequest } from "../dist/server/server.js";

const response = await handleRequest(new Request("https://remineph.online/"));
const html = await response.text();
if (
  !response.ok ||
  !html.includes("Five voices.") ||
  !html.includes("PULSE") ||
  !html.includes("<script")
) {
  throw new Error(`Homepage prerender failed (${response.status}).`);
}
await writeFile("dist/client/index.html", html);
async function files(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  return (
    await Promise.all(
      entries.map((e) =>
        e.isDirectory() ? files(`${dir}/${e.name}`) : `${dir}/${e.name}`,
      ),
    )
  ).flat();
}
const scripts = (await files("dist/client")).filter((file) =>
  file.endsWith(".js"),
);
const buffers = await Promise.all(scripts.map((file) => readFile(file)));
console.log(
  `Prerendered homepage: ${Buffer.byteLength(html)} bytes; no request-time rendering.`,
);
console.log(
  JSON.stringify({
    framework: "SolidJS 2.0.0-rc.21",
    javascript_files: scripts.length,
    javascript_bytes: buffers.reduce((n, b) => n + b.length, 0),
    javascript_gzip_bytes: buffers.reduce((n, b) => n + gzipSync(b).length, 0),
  }),
);
