Deployment and recovery instructions are in [docs/vps-deployment.md](/home/paulanthonyarriola/rescene-rhythm/docs/vps-deployment.md).

The API Worker hostname is `api.remineph.online`. Its origin credential is set with Wrangler secrets and never appears in this directory. `compose.yaml` runs the dedicated VPS API/database; its environment files and data are private and are not checked in. `Dockerfile` copies only the prebuilt static API binary.

`/download` streams the versioned `APK_OBJECT_KEY` directly from the `rescene` R2
bucket using the `APK_RELEASES` binding, before any VPS proxying. The bucket can
remain private with public bucket access disabled. GET/HEAD, conditional ETags,
and byte ranges support download clients and resuming. Missing R2 data returns
503 and never falls back to the VPS. `X-APK-Storage: r2` identifies this route.
The companion `/download` redirect remains unchanged.

Run `node --test infra/game-api/download.test.mjs` from the project root to verify
streaming, ranges, HEAD, conditionals, and failure behavior. Android build/publish
instructions are in [../android/README.md](../android/README.md).

`/updates/android.json` exposes only public release metadata from R2. Pinned
`/updates/android/<version>/RESCENE-Rhythm.apk` paths allow in-app downloads to
resume even when the current release changes. Separate `-emulator.apk` paths
and `?arch=x86_64` manifests support QA without bloating the phone APK. All update
traffic stays in Cloudflare and never proxies through the VPS.
