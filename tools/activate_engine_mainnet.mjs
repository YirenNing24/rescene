import {ssh,quote} from '/home/paulanthonyarriola/Desktop/fluentxverse/scripts/lib/cloud-ssh.mjs';
import {readFileSync,writeFileSync} from 'node:fs';
const root='/home/paulanthonyarriola/rescene-rhythm';
const state=JSON.parse(readFileSync(root+'/contracts/launch/elysium-20261111/state-launch.json'));if(state.status!=='verified')throw Error('Mainnet verification required');
const code=`const p=await Bun.stdin.json(),base='http://127.0.0.1:8090',project='7fe1ecf2-b715-43bc-ba03-3f0a1149bc5d';
const common={'Content-Type':'application/json','X-Forwarded-Proto':'https','X-Forwarded-Host':'engine.fluentxverse.com','Origin':'https://engine.fluentxverse.com'};
const login=await fetch(base+'/dashboard/auth/login',{method:'POST',headers:common,body:JSON.stringify({username:p.username,password:p.password})});if(!login.ok)throw Error('Operator login failed');
const cookie=login.headers.get('set-cookie')?.split(';')[0];const headers={...common,Cookie:cookie};
async function api(path,body){const r=await fetch(base+path,{method:body?'PUT':'GET',headers,body:body?JSON.stringify(body):undefined});if(!r.ok)throw Error('Project activation failed '+r.status);return await r.json();}
try{
 const detail=await api('/dashboard/projects/'+project);const before=detail.project;
 if(before.name!=='rescene-rhythm')throw Error('Unexpected project');
 const current=detail.importedContracts.filter(x=>x.chainId===99901);if(current.length!==8)throw Error('Expected eight Elysium app contracts');
 const after=(await api('/dashboard/projects/'+project+'/settings',{...before,environment:'production',allowedChains:[99901]})).project;
 const expected={...before,environment:'production',allowedChains:[99901],updatedAt:after.updatedAt};
 for(const key of Object.keys(before))if(JSON.stringify(after[key])!==JSON.stringify(expected[key]))throw Error('Unexpected project change');
 const w=detail.serverWallet;const wallet=await api('/dashboard/projects/'+project+'/wallets/'+w.id+'/detail');
 if(wallet.detail.nativeBalance.chainId!==99901||wallet.detail.nativeBalance.symbol!=='HYPE')throw Error('Project wallet network mismatch');
 console.log(JSON.stringify({project:after.name,projectId:project,environment:after.environment,allowedChains:after.allowedChains,gameContracts:current.map(x=>({name:x.name,address:x.contractAddress})),treasury:w.address,balance:wallet.detail.nativeBalance.value,symbol:'HYPE'}));
}finally{await fetch(base+'/dashboard/auth/logout',{method:'POST',headers});}`;
const py=`import json,subprocess
c=json.loads(subprocess.check_output(['docker','inspect','budol-gmr-engine-1']))[0];e=dict(x.split('=',1) for x in c['Config']['Env']);image=json.loads(subprocess.check_output(['docker','inspect','fluentxverse-server']))[0]['Config']['Image'];p={'username':e.get('GMR_ENGINE_OWNER_USERNAME','destrega'),'password':e.get('GMR_ENGINE_OWNER_PASSWORD','')}
subprocess.run(['docker','run','--rm','-i','--network','container:budol-gmr-engine-1','--entrypoint','bun',image,'--no-env-file','-e',${JSON.stringify(code)}],input=json.dumps(p),text=True,check=True)`;
try{const result=JSON.parse(ssh('python3 -c '+quote(py),{timeout:60000}));writeFileSync(root+'/contracts/deployments/elysium-engine-project.json',JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));}catch{console.error('Engine mainnet activation incomplete; private diagnostics suppressed.');process.exitCode=1;}
