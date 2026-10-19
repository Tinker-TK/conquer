import json, pathlib, re

def tables(path):
    lines = pathlib.Path(path).read_text(encoding='utf-8').splitlines()
    out = []
    i = 0
    while i < len(lines):
        if lines[i].startswith('|') and i + 1 < len(lines) and re.match(r'^\|\s*-+', lines[i + 1]):
            header = [c.strip() for c in lines[i].strip().strip('|').split('|')]
            rows = []
            j = i + 2
            while j < len(lines) and lines[j].startswith('|'):
                cells = [c.strip() for c in lines[j].strip().strip('|').split('|')]
                if len(cells) == len(header):
                    rows.append(dict(zip(header, cells)))
                j += 1
            out.append((header, rows))
            i = j
        else:
            i += 1
    return out

if __name__ == '__main__':
    for path in ['docs/遗物流派设计.md', 'docs/药水能力设计与投放方案.md']:
        print('===', path)
        for header, rows in tables(path):
            if '遗物' in header or '药水' in header:
                print(header, len(rows))
                for r in rows[:3]:
                    print(r)
