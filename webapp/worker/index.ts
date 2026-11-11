interface Fetcher { fetch(request: Request): Promise<Response> }
interface Storage {
  get<T>(key: string): Promise<T | undefined>;
  put<T>(key: string, value: T): Promise<void>;
  deleteAll(): Promise<void>;
  setAlarm(time: number): Promise<void>;
}
interface State { storage: Storage }
interface Namespace { idFromName(name: string): unknown; get(id: unknown): Fetcher }
interface Env { ASSETS: Fetcher; SESSIONS: Namespace; API_ORIGIN: string; GAME_API?: Fetcher }
interface LoginSession { access_token: string; refresh_token: string; expires_in: number; refresh_expires_at: number; access_until: number; user: unknown; rotation_id?: string }
const COOKIE = '__Host-rhythm';
const HEX = /^[a-f0-9]{64}$/;
const token = (): string => Array.from(crypto.getRandomValues(new Uint8Array(32)), n => n.toString(16).padStart(2, '0')).join('');
const json = (data: unknown, status = 200): Response => Response.json(data, {status, headers: {'Cache-Control':'no-store'}});
const error = (message: string, status = 400): Response => json({error:{message}}, status);
const cookie = (id: string, age = 2592000): string => `${COOKIE}=${id}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=${age}`;
export function allowed(method: string, path: string): boolean {
  if (method === 'GET') return /^\/mastery\/[a-f0-9]{12}$/.test(path) || /^\/(auth\/me|events|coop|progression|account\/security|records|leaderboards|leaderboard-publication|wallet|starlight|shop\/catalog|marketplace|inventory|profile\/media|challenges|social|social\/players|social\/events)$/.test(path) || /^\/players\/[a-f0-9]{32}(\/media\/[a-f0-9]{32})?$/.test(path) || /^\/social\/conversations\/[a-f0-9]{32}$/.test(path);
  if (method === 'POST') return /^\/mastery\/[a-f0-9]{12}\/[a-z_]+\/claim$/.test(path) || /^\/coop\/[a-f0-9]{32}\/(action|claim)$/.test(path) || /^\/(daily-login\/claim|coop\/invite|account\/password|account\/recovery-codes|shop\/purchase|inventory\/consume|collection\/(quote|action|equip)|progression\/equip|reports|challenges|social\/presence)$/.test(path) || /^\/events\/[a-z0-9_-]+\/missions\/[a-z0-9_]+\/claim$/.test(path) || /^\/missions\/[a-z0-9_]+\/claim$/.test(path) || /^\/challenges\/[a-f0-9]{32}$/.test(path) || /^\/social\/players\/[a-f0-9]{32}\/(follow|block)$/.test(path) || /^\/social\/conversations\/[a-f0-9]{32}\/(messages|read|typing)$/.test(path) || /^\/profile\/media\/(avatar|gallery)$/.test(path);
  return ['PUT','DELETE'].includes(method) && /^\/profile\/media\/(avatar|gallery)\/[a-f0-9]{32}$/.test(path);
}
function secured(response: Response): Response {
  const r = new Response(response.body, response);
  r.headers.set('X-Content-Type-Options','nosniff'); r.headers.set('X-Frame-Options','DENY');
  r.headers.set('Referrer-Policy','same-origin');
  r.headers.set('Strict-Transport-Security','max-age=31536000; includeSubDomains');
  r.headers.set('Permissions-Policy','camera=(),microphone=(),geolocation=()');
  r.headers.set('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self'; media-src 'none'; object-src 'none'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'");
  if (r.headers.get('Content-Type')?.includes('text/html')) r.headers.set('Cache-Control','no-cache');
  return r;
}
async function upstream(env: Env, path: string, method: string, body?: BodyInit | null, access?: string, contentType = 'application/json', ip?: string): Promise<Response> {
  const headers = new Headers({'Accept':'application/json'});
  if (body) headers.set('Content-Type', contentType);
  if (access) headers.set('Authorization', 'Bearer '+access);
  // Never trust browser-provided authorization, cookies, admin headers or target URLs.
  if (ip && env.GAME_API) headers.set('CF-Connecting-IP', ip);
  const request = new Request(env.API_ORIGIN+'/api/v1'+path, {method, headers, body, redirect:'manual', signal:AbortSignal.timeout(40000)});
  return env.GAME_API ? env.GAME_API.fetch(request) : fetch(request);
}
export class SessionVault {
  private queue: Promise<unknown> = Promise.resolve();
  private ctx: State;
  private env: Env;
  constructor(ctx: State, env: Env) { this.ctx=ctx; this.env=env; }
  async alarm(): Promise<void> { await this.ctx.storage.deleteAll(); }
  fetch(request: Request): Promise<Response> {
    // Serialize rotation and logout across concurrent requests and browser tabs.
    const result = this.queue.then(() => this.handle(request));
    this.queue = result.catch(() => undefined);
    return result;
  }
  private async save(session: LoginSession): Promise<void> {
    await this.ctx.storage.put('session', session);
    await this.ctx.storage.setAlarm(session.refresh_expires_at*1000);
  }
  private async handle(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === '/initialize' && request.method === 'POST') {
      const session = await request.json() as LoginSession;
      session.access_until = Date.now()+session.expires_in*1000;
      await this.save(session);
      return json({user: session.user});
    }
    let session = await this.ctx.storage.get<LoginSession>('session');
    if (!session || session.refresh_expires_at*1000 <= Date.now()) {
      await this.ctx.storage.deleteAll(); return error('Sign in to your backstage.',401);
    }
    if (url.pathname === '/logout') {
      const res = await upstream(this.env,'/auth/logout','POST',JSON.stringify({refresh_token:session.refresh_token}),undefined,'application/json',request.headers.get('CF-Connecting-IP') ?? undefined);
      if (!res.ok) return error('Could not sign out. Please retry.',503);
      await this.ctx.storage.deleteAll(); return json({ok:true});
    }
    let rotated = false;
    const rotate = async (): Promise<Response | null> => {
      if (!session) return error('Please sign in again.',401);
      // Persist a stable refresh request before the network call. A lost response
      // can be recovered with the backend's existing idempotent token rotation.
      session.rotation_id ??= token().slice(0,32); await this.save(session);
      const result = await upstream(this.env,'/auth/refresh','POST',JSON.stringify({refresh_token:session.refresh_token,request_id:session.rotation_id}),undefined,'application/json',request.headers.get('CF-Connecting-IP') ?? undefined);
      if (!result.ok) {
        if (result.status === 401) await this.ctx.storage.deleteAll();
        return error(result.status===401?'Your session expired. Please sign in again.':'Your session could not refresh. Please retry.',result.status===401?401:503);
      }
      const next = await result.json() as LoginSession;
      next.access_until = Date.now()+next.expires_in*1000;
      session = next; await this.save(next); rotated = true; return null;
    };
    if (session.access_until < Date.now()+60000 || session.rotation_id) { const failure = await rotate(); if (failure) return failure; }
    const path = url.pathname === '/session' ? '/auth/me' : url.pathname+url.search;
    const body = ['GET','HEAD'].includes(request.method) ? undefined : await request.arrayBuffer();
    const send = (): Promise<Response> => upstream(this.env,path,request.method,body,session!.access_token,request.headers.get('Content-Type') ?? 'application/json',request.headers.get('CF-Connecting-IP') ?? undefined);
    let res = await send();
    if (res.status === 401) { const failure = await rotate(); if (failure) return failure; res = await send(); }
    const response = new Response(res.body,{status:res.status,headers:{'Content-Type':res.headers.get('Content-Type') ?? 'application/json','Cache-Control':'no-store'}});
    if (rotated) response.headers.set('X-Session-Renewed','1');
    return response;
  }
}
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(request.url);
      if (url.pathname === '/download') return Response.redirect(env.API_ORIGIN+'/download',302);
      if (!url.pathname.startsWith('/api/')) return secured(await env.ASSETS.fetch(request));
      if (!['GET','POST','PUT','DELETE'].includes(request.method)) return secured(error('Method not allowed.',405));
      if (request.method !== 'GET' && request.headers.get('Origin') !== url.origin) return secured(error('Please submit this request from your backstage.',403));
      if (Number(request.headers.get('Content-Length') ?? 0)>8388608) return secured(error('Image must be smaller than 8 MB.',413));
      const path = url.pathname.slice(4);
      if (['/auth/login','/auth/register','/auth/recover'].includes(path) && request.method === 'POST') {
        const raw = await request.text();
        if (raw.length>4096) return secured(error('Request too large.',413));
        const res = await upstream(env,path,'POST',raw,undefined,'application/json',request.headers.get('CF-Connecting-IP') ?? undefined);
        if (!res.ok || path === '/auth/recover') return secured(new Response(res.body,{status:res.status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}}));
        const session = await res.json() as LoginSession;
        if (!session.access_token || !session.refresh_token) return secured(error('Sign in is temporarily unavailable.',503));
        const id = token(); const stub = env.SESSIONS.get(env.SESSIONS.idFromName(id));
        const initialized = await stub.fetch(new Request('https://session/initialize',{method:'POST',body:JSON.stringify(session)}));
        if (!initialized.ok) return secured(error('Sign in is temporarily unavailable.',503));
        const out = json({user:session.user}); out.headers.set('Set-Cookie',cookie(id)); return secured(out);
      }
      if (!['/session','/logout'].includes(path) && !allowed(request.method,path)) return secured(error('This action is available in the Android game.',404));
      if ((path==='/logout' && request.method!=='POST') || (path==='/session' && request.method!=='GET')) return secured(error('Method not allowed.',405));
      const id = request.headers.get('Cookie')?.match(/(?:^|;\s*)__Host-rhythm=([^;]+)/)?.[1] ?? '';
      if (!HEX.test(id)) return secured(error('Sign in to your backstage.',401));
      const body = request.method==='GET'?undefined:await request.arrayBuffer();
      if (body && body.byteLength>8388608) return secured(error('Image must be smaller than 8 MB.',413));
      const stub = env.SESSIONS.get(env.SESSIONS.idFromName(id));
      const out = await stub.fetch(new Request('https://session'+path+url.search,{method:request.method,headers:{'Content-Type':request.headers.get('Content-Type') ?? 'application/json','CF-Connecting-IP':request.headers.get('CF-Connecting-IP') ?? ''},body}));
      const response = new Response(out.body,out);
      if (out.headers.get('X-Session-Renewed') || path==='/session' && out.ok) response.headers.set('Set-Cookie',cookie(id));
      if (out.status===401 || path==='/logout' && out.ok) response.headers.set('Set-Cookie',cookie('',0));
      response.headers.delete('X-Session-Renewed');
      return secured(response);
    } catch { return secured(error('The connection was interrupted. Please retry.',503)); }
  }
};
