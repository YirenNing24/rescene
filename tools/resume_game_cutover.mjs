import{execFileSync}from'node:child_process';import{readFileSync,writeFileSync}from'node:fs';import{sshOptions,cloudHost}from'/home/paulanthonyarriola/Desktop/fluentxverse/scripts/lib/cloud-ssh.mjs';
const path='/home/paulanthonyarriola/rescene-rhythm/backend/data/vps-deployment/cutover.json',state=JSON.parse(readFileSync(path));if(state.phase!=='source-stopped')throw Error('Not a paused migration');
const remote=cmd=>execFileSync('ssh',[...sshOptions,'root@'+cloudHost,cmd],{encoding:'utf8',timeout:120000});
const value=remote("cd /opt/remine && docker compose exec -T falkordb sh -c 'REDISCLI_AUTH=\"$REDIS_PASSWORD\" redis-cli --json GRAPH.QUERY rescene \"MATCH(n) RETURN count(n)\"'");
if(JSON.stringify(JSON.parse(value)[1])!==JSON.stringify(state.nodeCensus[1]))throw Error('Graph rows differ');
state.phase='restored-verified';writeFileSync(path,JSON.stringify(state,null,2));
console.log(remote('cd /opt/remine && docker compose up -d --wait api'));
state.phase='vps-primary';state.activatedAt=new Date().toISOString();writeFileSync(path,JSON.stringify(state,null,2));console.log('PASS graph restore census, VPS service startup and health check.');
