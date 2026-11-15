import {downloadApk, latestDownload} from './download.js';
import {releaseManifest, updateObject} from './updates.js';

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/download') return latestDownload(request, env);
    if (url.pathname === '/updates/android.json') return releaseManifest(request, env);
    const pinnedApk = updateObject(url.pathname);
    if (pinnedApk) return downloadApk(request, {...env, APK_OBJECT_KEY:pinnedApk});
    if (!env.ORIGIN_EDGE_SECRET) return Response.json({error:{message:'Service unavailable'}},{status:503});
    const admin = url.pathname.startsWith('/api/admin/v1/');
    if (!(url.pathname === '/healthz' || url.pathname.startsWith('/api/v1/') || admin)) return new Response('Not found', {status:404});
    if (admin && !/^[a-f0-9]{64}$/.test(request.headers.get('X-Admin-Signature') ?? '')) return new Response('Not found', {status:404});
    if (Number(request.headers.get('Content-Length') ?? 0) > 8388608) return new Response('Request too large',{status:413});
    const target = new URL(env.API_ORIGIN + '/rescene' + url.pathname + url.search);
    const headers = new Headers(request.headers);
    headers.delete('Forwarded'); headers.delete('X-Forwarded-For'); headers.delete('X-Real-IP');
    headers.set('X-Remine-Edge', env.ORIGIN_EDGE_SECRET);
    headers.set('X-Remine-Client-IP', request.headers.get('CF-Connecting-IP') ?? '');
    if (!admin) for (const key of [...headers.keys()]) if (key.toLowerCase().startsWith('x-admin-')) headers.delete(key);
    try {
      const upstream = await fetch(target, {method:request.method,headers,body:['GET','HEAD'].includes(request.method)?undefined:request.body,redirect:'manual',signal:AbortSignal.timeout(45000)});
      const response = new Response(upstream.body, upstream);
      response.headers.set('Cache-Control','no-store');response.headers.set('X-Content-Type-Options','nosniff');
      return response;
    } catch { return Response.json({error:{message:'The server is temporarily unavailable. Please retry.'}},{status:503,headers:{'Cache-Control':'no-store'}}); }
  }
};
