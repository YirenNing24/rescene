// Cold snapshot migration. Never run after the VPS has accepted player writes.
import {execFileSync} from 'node:child_process';import{readFileSync,writeFileSync,existsSync}from'node:fs';import{createHash}from'node:crypto';
import{sshOptions,cloudHost}from'/home/paulanthonyarriola/Desktop/fluentxverse/scripts/lib/cloud-ssh.mjs';
const root='/home/paulanthonyarriola/rescene-rhythm',priv=root+'/backend/data/vps-deployment',stateFile=priv+'/cutover.json',target='root@'+cloudHost;
const run=(cmd,args,opts={})=>execFileSync(cmd,args,{encoding:'utf8',timeout:120000,...opts});const remote=cmd=>run('ssh',[...sshOptions,target,cmd]);
if(existsSync(stateFile))throw Error('Cutover checkpoint exists. Inspect it before any further migration.');
const state={phase:'source-pausing',at:new Date().toISOString()};const save=()=>writeFileSync(stateFile,JSON.stringify(state,null,2),{mode:0o600});save();
run('systemctl',['--user','stop','remine-game-api.service','remine-admin-tunnel.service']);
const query='MATCH(n) RETURN count(n)';const census=run('docker',['exec','rescene-rhythm-falkordb-1','redis-cli','--json','GRAPH.QUERY','rescene',query]);state.nodeCensus=JSON.parse(census);state.phase='source-stopped';save();
console.log(run('docker',['exec','rescene-rhythm-falkordb-1','redis-cli','SAVE']).trim());
run('docker',['cp','rescene-rhythm-falkordb-1:/data/dump.rdb',priv+'/migration.rdb']);state.snapshotSHA256=createHash('sha256').update(readFileSync(priv+'/migration.rdb')).digest('hex');save();
run('tar',['-czf',priv+'/media.tar.gz','--exclude=./vps-deployment','-C',root+'/backend/data','.']);
for(const file of ['migration.rdb','media.tar.gz'])run('scp',[...sshOptions,priv+'/'+file,target+':/opt/remine/backups/'+file]);
const checksum=remote('sha256sum /opt/remine/backups/migration.rdb').split(' ')[0];if(checksum!==state.snapshotSHA256)throw Error('Snapshot transfer checksum differs');
console.log(remote('test ! -f /opt/remine/database/dump.rdb && test ! -d /opt/remine/database/appendonlydir && install -m 600 /opt/remine/backups/migration.rdb /opt/remine/database/dump.rdb && tar -xzf /opt/remine/backups/media.tar.gz -C /opt/remine/data && chown -R 65532:65532 /opt/remine/data && cd /opt/remine && cp bootstrap-template.json bootstrap.json && docker compose -f compose.yaml -f bootstrap.json up -d --wait falkordb'));
const restored=remote("cd /opt/remine && docker compose exec -T falkordb sh -c 'REDISCLI_AUTH=\"$REDIS_PASSWORD\" redis-cli --json GRAPH.QUERY rescene \"MATCH(n) RETURN count(n)\"'");
if(JSON.stringify(JSON.parse(restored)[1])!==JSON.stringify(state.nodeCensus[1]))throw Error('Graph census differs after restore');
console.log(remote("cd /opt/remine && docker compose exec -T falkordb sh -c 'REDISCLI_AUTH=\"$REDIS_PASSWORD\" redis-cli CONFIG SET appendonly yes'"));
let persistence='';
for(let i=0;i<20;i++){
 persistence=remote("cd /opt/remine && docker compose exec -T falkordb sh -c 'REDISCLI_AUTH=\"$REDIS_PASSWORD\" redis-cli INFO persistence'");
 if(persistence.includes('aof_rewrite_in_progress:0')&&persistence.includes('aof_last_bgrewrite_status:ok'))break;
 await new Promise(resolve=>setTimeout(resolve,1000));
}
if(!persistence.includes('aof_rewrite_in_progress:0'))throw Error('Wait for initial AOF snapshot before continuing');
console.log(remote('cd /opt/remine && docker compose up -d --wait falkordb'));
state.phase='restored-verified';save();
console.log(remote('cd /opt/remine && docker compose up -d --wait api'));
state.phase='vps-primary';state.activatedAt=new Date().toISOString();save();
console.log('VPS primary started. Snapshot SHA-256 and exact graph node census match. Local API/tunnel remain stopped.');
