// Stream APK bytes from R2. This route must never fall through to the VPS.
export async function downloadApk(request, env) {
  const unavailable = () => new Response('Download temporarily unavailable', {status:503, headers:{'Cache-Control':'no-store'}});
  if (!['GET', 'HEAD'].includes(request.method)) return new Response('Method not allowed', {status:405, headers:{Allow:'GET, HEAD'}});
  if (!env.APK_RELEASES || !env.APK_OBJECT_KEY) return unavailable();
  try {
    const object = await env.APK_RELEASES.head(env.APK_OBJECT_KEY);
    if (!object) return unavailable();
    const headers = new Headers({
      'Content-Type':'application/vnd.android.package-archive',
      'Content-Disposition':'attachment; filename="RESCENE-Rhythm.apk"',
      'Accept-Ranges':'bytes',
      'ETag':object.httpEtag,
      'Last-Modified':object.uploaded.toUTCString(),
      'Cache-Control':'public, max-age=0, must-revalidate',
      'X-Content-Type-Options':'nosniff',
      'X-APK-Storage':'r2',
    });
    const noneMatch = request.headers.get('If-None-Match');
    if (noneMatch?.split(',').some(tag => tag.trim() === '*' || tag.trim().replace(/^W\//, '') === object.httpEtag)) return new Response(null, {status:304, headers});
    headers.set('Content-Length', String(object.size));
    if (request.method === 'HEAD') return new Response(null, {headers});
    let range;
    const rangeHeader = request.headers.get('Range');
    const ifRange = request.headers.get('If-Range');
    const matchesIfRange = !ifRange || ifRange === object.httpEtag || (Number.isFinite(Date.parse(ifRange)) && Math.floor(object.uploaded.getTime() / 1000) * 1000 <= Date.parse(ifRange));
    if (rangeHeader && matchesIfRange) {
      // Ignore unsupported/malformed multi-ranges; reject valid but unsatisfiable ranges.
      const match = /^bytes=(\d*)-(\d*)$/.exec(rangeHeader);
      if (match && (match[1] || match[2])) {
        const start = match[1] ? Number(match[1]) : Math.max(0, object.size - Number(match[2]));
        const end = match[1] && match[2] ? Math.min(Number(match[2]), object.size - 1) : object.size - 1;
        if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start >= object.size || start > end || (!match[1] && Number(match[2]) === 0)) {
          headers.set('Content-Range', `bytes */${object.size}`); headers.set('Content-Length','0');
          return new Response(null, {status:416, headers});
        }
        range = {offset:start, length:end-start+1};
        headers.set('Content-Range', `bytes ${start}-${end}/${object.size}`);
        headers.set('Content-Length',String(range.length));
      }
    }
    const data = await env.APK_RELEASES.get(env.APK_OBJECT_KEY, range ? {range} : undefined);
    if (!data?.body) return unavailable();
    return new Response(data.body, {status:range ? 206 : 200, headers});
  } catch { return unavailable(); }
}
