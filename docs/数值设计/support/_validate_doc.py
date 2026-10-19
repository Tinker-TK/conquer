import pathlib, re
p = pathlib.Path('docs/数值设计/数值框架与全量数值.md')
lines = p.read_text(encoding='utf-8').splitlines()
errors = []
i = 0
while i < len(lines):
    if lines[i].startswith('|') and i + 1 < len(lines) and re.match(r'^\|\s*-+', lines[i + 1]):
        header = [c for c in lines[i].strip().strip('|').split('|')]
        j = i + 2
        while j < len(lines) and lines[j].startswith('|'):
            cells = [c for c in lines[j].strip().strip('|').split('|')]
            if len(cells) != len(header):
                errors.append((j + 1, len(header), len(cells), lines[j][:120]))
            j += 1
        i = j
    else:
        i += 1
print('lines', len(lines), 'errors', len(errors))
for e in errors[:30]:
    print(e)
print('tables', sum(1 for l in lines if l.startswith('|---') or re.match(r'^\|\s*-+', l)))
