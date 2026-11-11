import { defineConfig } from "vite";
import solid from "@solidjs/vite-plugin";

export default defineConfig({
  plugins: [
    solid({ start: { renderMode: "async", devtools: false }, ssr: true }),
  ],
  server: { host: "127.0.0.1", port: 5173 },
  build: { target: "es2022", assetsInlineLimit: 0 },
});
