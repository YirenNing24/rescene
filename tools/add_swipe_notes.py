#!/usr/bin/env python3
"""Author spaced upward-swipe accents without changing note times or counts."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INTERVALS = {'Easy': 8.0, 'Normal': 6.0, 'Hard': 4.5, 'Ultra Hard': 3.5}


def add_swipes(chart):
    quarter = 60.0 / chart['tempo']
    ticks = chart['ticks_per_beat']
    notes = []
    for lane, track in enumerate(chart['tracks']):
        elapsed = 0
        for bar in track['bars']:
            for note in bar['notes']:
                if note['kind'] == 'swipe':
                    note['kind'], note['swipe'] = 'tap', False
                at = chart['offset_seconds'] + (elapsed + note['pos'] / ticks) * quarter
                duration = 0 if note['kind'] == 'tap' else note['len'] / ticks * quarter
                notes.append((at, lane, duration, note))
            elapsed += bar.get('quarters_count', 4)
    notes.sort(key=lambda row: (row[0], row[1]))
    next_at = 6.0
    count = 0
    for at, lane, _, note in notes:
        if note['kind'] != 'tap' or at < next_at or at > chart['duration_seconds'] - 2:
            continue
        # Leave chords and ribbon sections intact, with room to lift a finger.
        if any(other is not note and (abs(t - at) < .12 or
               other['kind'] in ('hold', 'slide') and t - .25 < at < t + duration + .25 or
               other_lane == lane and abs(t - at) < .35)
               for t, other_lane, duration, other in notes):
            continue
        note['kind'], note['swipe'] = 'swipe', True
        count += 1
        next_at = at + INTERVALS[chart['difficulty']]
    return count


def main():
    catalog = json.loads((ROOT / 'scripts/song_catalog.gd').read_text().split('=', 1)[1])
    count = 0
    for song in catalog:
        for path in sorted((ROOT / 'assets/beatmaps' / song['id']).glob('*.json')):
            chart = json.loads(path.read_text())
            added = add_swipes(chart)
            if not added:
                raise RuntimeError(f'No safe swipe placement: {path}')
            content = json.dumps(chart, ensure_ascii=False, separators=(',', ':'))
            path.write_text(content + '\n')
            path.with_suffix('.tres').write_text('[gd_resource type="JSON" format=3]\n\n[resource]\ndata = ' + content + '\n')
            count += added
    print(f'Authored {count} spaced swipe accents across {len(catalog) * 4} charts; note times and counts preserved.')


if __name__ == '__main__':
    main()
