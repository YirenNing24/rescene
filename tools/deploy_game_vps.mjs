// Stage infrastructure without copying player data or starting a second writer.
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {sshOptions,cloudHost} from '/home/paulanthonyarriola/Desktop/fluentxverse/scripts/lib/cloud-ssh.mjs';
const root='/home/paulanthonyarriola/rescene-rhythm',target='root@'+cloudHost;
const remote=cmd=>execFileSync('ssh',[...sshOptions,target,cmd],{encoding:'utf8',timeout:120000});
remote('install -d -m 700 /opt/remine /opt/remine/database /opt/remine/data /opt/remine/backups && install -d -m 755 /opt/remine/releases');
for(const [source,name] of [['backend/bin/rescene-api-vps','rescene-api'],['infra/game-api/Dockerfile','Dockerfile'],['infra/game-api/.dockerignore','.dockerignore'],['infra/game-api/bootstrap-template.json','bootstrap-template.json'],['infra/game-api/compose.yaml','compose.yaml'],['backend/data/vps-deployment/api.env','api.env'],['backend/data/vps-deployment/database.env','database.env']])execFileSync('scp',[...sshOptions,root+'/'+source,target+':/opt/remine/'+name],{timeout:60000});
console.log(remote('chmod 600 /opt/remine/api.env /opt/remine/database.env; chmod 755 /opt/remine/rescene-api; cd /opt/remine && docker compose build api'));
