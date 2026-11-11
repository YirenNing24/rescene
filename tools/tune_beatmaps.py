#!/usr/bin/env python3
"""Redistribute sub-100ms lane repeats; keep all authored note times unchanged."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def tune(c):
    q=60/c['tempo'];ticks=c['ticks_per_beat'];notes=[]
    for lane,track in enumerate(c['tracks']):
        elapsed=0
        for bi,bar in enumerate(track['bars']):
            for n in bar['notes']:notes.append((c['offset_seconds']+(elapsed+n['pos']/ticks)*q,lane,bi,bar,n))
            elapsed+=bar.get('quarters_count',4)
    notes.sort(key=lambda v:v[0]);last={};moves=[]
    for t,lane,bi,bar,n in notes:
        if t<last.get(lane,-999)+.1:
            options=[i for i in range(5) if t>=last.get(i,-999)+.1]
            if not options:raise RuntimeError('No playable lane')
            target=min(options,key=lambda x:abs(x-lane))
            if n['kind']=='slide':
                for point in n['curve']:point['lane']=max(0,min(4,point['lane']+target-lane))
            moves.append((bar,n,c['tracks'][target]['bars'][bi]));lane=target
        last[lane]=t
    for old,n,new in moves:old['notes'].remove(n);new['notes'].append(n)
    for track in c['tracks']:
        for bar in track['bars']:bar['notes'].sort(key=lambda n:n['pos'])
    return len(moves)
def main():
    count=0
    for p in (ROOT/'assets/beatmaps').glob('*/*.json'):
        c=json.loads(p.read_text());n=tune(c)
        if n:p.write_text(json.dumps(c,ensure_ascii=False,separators=(',',':'))+'\n');count+=n
    print(f'Redistributed {count} rapid lane repeats; musical timing retained.')
if __name__=='__main__':main()
