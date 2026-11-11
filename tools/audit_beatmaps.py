#!/usr/bin/env python3
"""Structural/playability review; musical timing still requires listening review."""
import json, math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def audit():
    charts=json.loads((ROOT/'backend/charts.json').read_text());results=[];errors=[]
    for c in charts:
        notes=c['notes']; counts={k:sum(n['kind']==k for n in notes) for k in ['tap','hold','slide']}; issues=[]
        occupied=[];last={};chords={}
        for i,n in enumerate(notes):
            t=n['time'];lane=n['lane'];duration=n.get('duration',0)
            if not all(math.isfinite(v) for v in [t,lane,duration]) or t<0 or t+duration>c['duration']+.001 or not 0<=lane<=4: issues.append(f'{i}: invalid bounds')
            if t<last.get(lane,-999)+.1: issues.append(f'{i}: same lane less than 100 ms apart')
            last[lane]=t;chords[round(t,3)]=chords.get(round(t,3),0)+1
            for end,occupied_lane,kind in occupied:
                if t<end-.01 and (kind=='slide' or occupied_lane==lane):issues.append(f'{i}: note conflicts with active ribbon')
            occupied=[v for v in occupied if v[0]>t]
            if n['kind']!='tap':occupied.append((t+duration,lane,n['kind']))
            if n['kind']=='slide':
                curve=n.get('curve',[])
                if len(curve)<2 or curve[0]['at']!=0 or curve[-1]['at']!=1:issues.append(f'{i}: incomplete curve')
                for a,b in zip(curve,curve[1:]):
                    if b['at']<=a['at'] or not 0<=b['lane']<=4:issues.append(f'{i}: invalid curve segment')
                    elif abs(b['lane']-a['lane'])*1.5/((b['at']-a['at'])*duration)>10:issues.append(f'{i}: curve too fast')
        max_chord=max(chords.values(),default=0)
        if max_chord>{'Easy':2,'Normal':3,'Hard':4,'Ultra Hard':5}[c['difficulty']]:issues.append('chord too large')
        results.append({'song':c['title'],'difficulty':c['difficulty'],'revision':c['revision'],'notes':len(notes),'types':counts,'max_chord':max_chord,'structural_issues':issues,'listening_review':'pending'})
        errors.extend(f"{c['title']} / {c['difficulty']}: {e}" for e in issues)
    output={'charts':len(results),'structural_pass':not errors,'listening_review':'Required before public launch; automated checks do not establish musical alignment.','results':results}
    path=ROOT/'output/beatmap-review.json';path.parent.mkdir(exist_ok=True);path.write_text(json.dumps(output,indent=2)+'\n')
    print(f'{len(results)} charts reviewed; {len(errors)} structural issues. Report: {path}')
    for e in errors[:30]:print(e)
    return bool(errors)
if __name__=='__main__':raise SystemExit(audit())
