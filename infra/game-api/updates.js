const VERSION = /^[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}$/;
export function updateObject(path) {
  const match = /^\/updates\/android\/([^/]+)\/(RESCENE-Rhythm(?:-emulator)?\.apk)$/.exec(path);
  return match && VERSION.test(match[1]) ? `android/${match[1]}/${match[2]}` : null;
}
export async function releaseManifest(request, env) {
  if (!['GET','HEAD'].includes(request.method)) return new Response('Method not allowed',{status:405,headers:{Allow:'GET, HEAD'}});
  const unavailable = () => Response.json({error:'Updates temporarily unavailable'},{status:503,headers:{'Cache-Control':'no-store'}});
  if (!env.APK_RELEASES || !env.APK_OBJECT_KEY) return unavailable();
  try {
    const architecture = new URL(request.url).searchParams.get('arch');
    if (architecture && !['arm64-v8a','x86_64'].includes(architecture)) return new Response('Unsupported architecture',{status:400});
    const emulator = architecture === 'x86_64';
    const filename = emulator ? 'RESCENE-Rhythm-emulator.apk' : 'RESCENE-Rhythm.apk';
    const object = await env.APK_RELEASES.get(env.APK_OBJECT_KEY.replace(/[^/]+$/, emulator ? 'emulator-release.json' : 'release.json'));
    if (!object?.body || object.size > 65536) return unavailable();
    const data = await object.json();
    if (!VERSION.test(data.version) || !Number.isSafeInteger(data.version_code) || data.version_code <= 0 || !Number.isSafeInteger(data.bytes) || data.bytes <= 0 || data.bytes > 1073741824 || !/^[a-f0-9]{64}$/.test(data.sha256) || !/^[a-f0-9]{64}$/.test(data.signing_certificate_sha256)) return unavailable();
    if (env.APK_OBJECT_KEY !== `android/${data.version}/RESCENE-Rhythm.apk`) return unavailable();
    if (emulator && (data.file !== filename || !Array.isArray(data.architectures) || !data.architectures.includes('x86_64'))) return unavailable();
    // Return only distribution metadata. Never expose private server credentials.
    const result = {format_version:1,version:data.version,version_code:data.version_code,bytes:data.bytes,sha256:data.sha256,signing_certificate_sha256:data.signing_certificate_sha256,download_url:`https://api.remineph.online/updates/android/${data.version}/${filename}`,release_notes:String(data.release_notes ?? '').slice(0,2000)};
    const response = Response.json(result,{headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
    return request.method === 'HEAD' ? new Response(null,response) : response;
  } catch { return unavailable(); }
}
