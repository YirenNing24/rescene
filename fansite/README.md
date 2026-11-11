# RESCENE Fan Collective

An independent RESCENE fan site at https://remineph.online, inspired by https://blackpink-fansite.com/.

## Stack and rendering

The application uses **SolidJS 2.0.0-rc.21**, `@solidjs/web` at the same version, TypeScript, and the official Solid Vite plugin. Solid 2 is a prerelease; the runtime and compiler versions are pinned in `package.json` and `package-lock.json`.

There is no React, Next.js, or Vinext dependency. The unused React starter components, database examples, connector scaffolding, and Tailwind build pipeline were removed. Styling is plain CSS; the existing Lucide icon geometry is compiled into native Solid SVG components and retains its ISC license.

The build renders the full homepage once into `dist/client/index.html`. Solid hydrates that HTML in the browser to enable member dialogs, collection saves, filtering, the quiz, search, and mobile navigation. Cloudflare Workers Static Assets serves the HTML and assets directly, without running an SSR function on each request. Hashed JS and CSS receive a one-year immutable browser cache policy. HTML keeps Cloudflare's revalidation policy so deployments update normally.

## Commands

- `npm install` — install pinned dependencies.
- `npm run dev` — start Solid's SSR development server at http://127.0.0.1:5173.
- `npm run check` — type-check application, configuration, and browser tests.
- `npm run build` — build client/server bundles and prerender the static homepage.
- `npm test` — test the exact prerendered build through local Wrangler using Playwright and Chrome. Run the build first.
- `npm run deploy:cloudflare` — check, rebuild, and publish through the existing Wrangler login.

Tests use locally installed Google Chrome. They cover the no-JavaScript homepage, hydrated interactions, collection persistence, existing preferences from the React version, search focus, quiz feedback/scoring/replay, music filters, mobile navigation, image loading, icon geometry, and horizontal overflow. Desktop/mobile captures are saved in `../previews/fansite-solid-*.png`.

## Cloudflare deployment

`wrangler.cloudflare.json` deploys the static build to the existing `remineph-fansite` Worker and retains the `remineph.online/*` route, Cloudflare account, DNS, and TLS configuration. A route is used because the zone has an existing externally managed apex DNS record. The private Sites preview is separate and is not updated by this command.

The Solid server bundle is used only at build time and is not uploaded to Cloudflare. The `.openai/hosting.json` retains the prior Site identity and describes the static output for compatibility.

## Performance comparison

Measured across all production client JavaScript files, compressed independently with Node gzip:

| Build | JavaScript files | Raw bytes | Gzip bytes |
| --- | ---: | ---: | ---: |
| Previous React 19 / Vinext | 9 | 413,584 | 125,305 |
| Solid 2 | 1 | 97,540 | 33,994 |

The migration reduced the production JavaScript total by 72.9% with gzip (76.4% uncompressed). The build prints the current raw and gzip totals. This measures shipped code size, not a claim about an equivalent percentage improvement in page-load time. Images and visual content are preserved.

## Features and local data

- Five member profiles and PULSE concept-photo portraits.
- Filterable selected discography linking to Spotify search.
- Four-question quiz with feedback, scoring, and replay.
- Photocards saved in localStorage under the existing `remine-cards` key.
- Favorite song retained under the existing `remine-pick` key.
- Search, Command/Ctrl+K, accessible dialogs, mobile navigation, reduced-motion styling.

Fansite interactions remain local. The navigation and hero link to https://rhythm.remineph.online, the separate Solid 2 game companion with shared game accounts, cards, rewards, social features, and Android downloads. There is no song playback or gameplay in the companion. A `.gdignore` prevents Godot from importing this website's dependencies and assets.

## Credits

PULSE photography: https://kpopping.com/kpics/rescene-4th-mini-album-pulse-concept-photos

Originals are in `../output/cards/pulse-le-set/sources/`; member assignments follow that archive's README: group 01, Woni 10, Liv 08, Minami 06, May 04, Zena 03. Existing album artwork comes from `../assets/art/covers/` and the song catalog. WebP files preserve the previous website assets. Photography, music, and artwork belong to their respective owners.

Official video destination: https://www.youtube.com/@RESCENE_official

Lucide icon license: `src/lucide-LICENSE`.
