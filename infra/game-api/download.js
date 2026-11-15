import {updateObject} from './updates.js';

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
      'Content-Disposition':`attachment; filename="${downloadName(env.APK_OBJECT_KEY)}"`,
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

function downloadName(key) {
  const match = /^android\/([0-9]+\.[0-9]+\.[0-9]+)\/(RESCENE-Rhythm(?:-emulator)?)\.apk$/.exec(key ?? '');
  return match ? `${match[2]}-${match[1]}.apk` : 'RESCENE-Rhythm.apk';
}

// Resolve the mutable entry point before any bytes are sent. New browser
// downloads resume against a version-pinned URL even after a release changes.
export async function latestDownload(request, env) {
  if (!['GET','HEAD'].includes(request.method)) return new Response('Method not allowed',{status:405,headers:{Allow:'GET, HEAD'}});
  const path = '/updates/' + env.APK_OBJECT_KEY;
  if (!env.APK_RELEASES || !updateObject(path)) return new Response('Download temporarily unavailable',{status:503,headers:{'Cache-Control':'no-store'}});
  if (request.method === 'GET' && request.headers.has('Range')) {
    // A partial file from the former mutable URL may belong to another build.
    // A full 200 response tells download managers to restart, never append.
    const headers = new Headers(request.headers);
    for (const name of ['Range','If-Range','If-None-Match','If-Modified-Since']) headers.delete(name);
    const response = await downloadApk(new Request(request,{headers}),env);
    response.headers.set('Cache-Control','no-store');
    response.headers.set('Accept-Ranges','none');
    return response;
  }
  return new Response(null,{status:307,headers:{Location:new URL(path,request.url).href,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
}
