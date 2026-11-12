import releases from './card-releases.json';
export class ApiError extends Error {
  constructor(message: string, public status: number) { super(message); }
}
export async function api<T>(path: string, body?: unknown, method?: string): Promise<T> {
  const binary = body instanceof Blob;
  const response = await fetch('/api'+path, {method: method ?? (body===undefined?'GET':'POST'), credentials:'same-origin', headers: body===undefined?undefined:{'Content-Type':binary?body.type:'application/json'}, body:body===undefined?undefined:binary?body:JSON.stringify(body)});
  const data = await response.json() as T & {error?: {message?: string}};
  if (!response.ok) {
    if (response.status===401) window.dispatchEvent(new Event('session-expired'));
    throw new ApiError(data.error?.message ?? 'Could not complete this request.',response.status);
  }
  return data;
}
export const requestID = (): string => crypto.randomUUID().replaceAll('-','');
export const photoURL = (url?: string): string => url ? '/api'+url.replace(/^\/api\/v1/,'') : '';
export const number = (n?: number | string): string => n===undefined ? '—' : Number(n).toLocaleString(undefined,{maximumFractionDigits:2});
export const title = (value: string): string => value.replaceAll('_',' ').replace(/\b\w/g,c=>c.toUpperCase());
export const members: string[] = ['Woni','Liv','Minami','May','Zena'];
export const cardReleases = releases;
export const cardImage = (member?: string, setID = 'pulse'): string => {
  const release = releases.find(r=>r.set_id===setID);
  const name = (member ?? 'woni').toLowerCase();
  return release && members.some(m=>m.toLowerCase()===name) ? '/images/cards/v1/'+release.slug+'/'+name+'.webp' : '';
};
export const isCard = (id: string): boolean => id.startsWith('pulse_');
