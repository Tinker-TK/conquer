"""Game configuration catalog: engine snapshot, portable HTML, validated local apply."""
from pathlib import Path
from http.server import BaseHTTPRequestHandler, HTTPServer
from datetime import datetime
import argparse
import copy
import hashlib
import json
import math
import os
import re
import secrets
import subprocess
import tempfile
import webbrowser

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
GODOT = os.environ.get('GODOT_EXE', 'D:/Godot4/Godot_v4.6.2-stable_win64_console.exe')
HTML = ROOT / 'docs/game_config_catalog.html'
FORMAT = 'ballsprite-config-catalog-v1'
CUSTOM_FIELDS = 'tools/config_catalog/custom_fields.json'
EXPORT_SCRIPT = 'addons/game_config_editor/config_catalog_export.gd'
FAMILIES = {
    'cards': 'data/cards/card_definition.gd',
    'card_effects': 'data/card_effects/card_effect.gd',
    'units': 'data/units/unit_data.gd',
    'skills': 'data/skills/skill_base.gd',
    'relics': 'data/relics/relic_definition.gd',
    'potions': 'data/potions/potion_definition.gd',
}
NEW_TYPES = {'bool': (1, 'bool'), 'int': (2, 'int'), 'float': (3, 'float'), 'text': (4, 'String')}


def family_of(record):
    if record['script'] == 'res://' + FAMILIES['card_effects']:
        return 'card_effects'
    return record['group']


def fingerprints(root):
    hashes = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for folder in ('data', 'scripts/skills', 'scenes/units') for p in (root / folder).rglob('*')
            if p.is_file() and p.suffix in ('.tres', '.gd', '.tscn')}
    custom = root / CUSTOM_FIELDS
    if custom.exists():
        hashes[CUSTOM_FIELDS] = hashlib.sha256(custom.read_bytes()).hexdigest()
    return hashes


def values_equal(left, right):
    if type(left) in (int, float) and type(right) in (int, float):
        return math.isclose(left, right, rel_tol=1e-6, abs_tol=1e-6)
    if isinstance(left, list) and isinstance(right, list):
        return len(left) == len(right) and all(values_equal(a, b) for a, b in zip(left, right))
    return left == right


def snapshot(root=ROOT):
    """Use the engine, including script defaults, rather than interpreting GDScript."""
    hashes = fingerprints(root)
    with tempfile.TemporaryDirectory(prefix='ballsprite-catalog-') as folder:
        output = Path(folder) / 'snapshot.json'
        env = dict(os.environ)
        env['APPDATA'] = env['TEMP']
        env['LOCALAPPDATA'] = env['TEMP']
        result = subprocess.run([GODOT, '--headless', '--path', str(root), '--script',
                                 'res://' + EXPORT_SCRIPT, '--', str(output), '--no-mcp-server'],
                                capture_output=True, timeout=45, env=env)
        log = (result.stdout + result.stderr).decode('utf-8', errors='replace')
        errors = [line for line in log.splitlines() if 'ERROR:' in line
                  and 'Failed to read the root certificate store' not in line]
        if result.returncode or not output.exists() or errors:
            raise ValueError('游戏配置读取失败：\n' + log[-5000:])
        data = json.loads(output.read_text(encoding='utf-8'))
    if hashes != fingerprints(root):
        raise ValueError('读取期间游戏配置发生变化，请保存编辑器内容后重试。')
    data['file_hashes'] = hashes
    for record in data['records']:
        record['file'] = record['id'].split('::')[0]
        record['group'] = record['file'].split('/')[3]
        record['used_by'] = []
        for field in record['fields']:
            if field['name'] in ('unit_type', 'unit_team', 'unit_english_name', 'id'):
                field['editable'] = False
            field['base'] = copy.deepcopy(field['value'])
    index = {row['id']: row for row in data['records']}
    for record in data['records']:
        for field in record['fields']:
            if not field['editable']:
                refs = field['value'] if isinstance(field['value'], list) else [field['value']]
                for ref in refs:
                    if isinstance(ref, str) and ref in index:
                        index[ref]['used_by'].append(record['id'])
    # Scene associations show which actual units read each resource.
    for path in sorted((root / 'scenes/units').glob('*.tscn')):
        text = path.read_text(encoding='utf-8')
        for ref in re.findall(r'path="(res://data/units/[^"\n]+)"', text):
            if ref in index:
                index[ref]['used_by'].append('res://' + path.relative_to(root).as_posix())
    data.update(format=FORMAT, generated=datetime.now().isoformat(timespec='seconds'))
    custom = root / CUSTOM_FIELDS
    data['custom_columns'] = json.loads(custom.read_text(encoding='utf-8')) if custom.exists() else []
    data['pending_columns'] = []
    data['pending_rows'] = []
    for record in data['records']:
        for field in record['fields']:
            column = next((c for c in data['custom_columns'] if c['family'] == family_of(record) and c['name'] == field['name']), None)
            if column:
                field['label'] = column['label']
                field['description'] = column['description']
    data['records'].sort(key=lambda row: row['id'])
    data['snapshot_id'] = hashlib.sha256(json.dumps(data['records'], sort_keys=True).encode()).hexdigest()[:20]
    return data


def html_text(data):
    embedded = json.dumps(data, ensure_ascii=False).replace('<', '\\u003c')
    return (HERE / 'catalog.sheet.html').read_text(encoding='utf-8').replace('__CATALOG_DATA__', embedded)


def build(data=None):
    data = snapshot() if data is None else data
    HTML.write_text(html_text(data), encoding='utf-8')
    return data


def read_document(path):
    text = Path(path).read_text(encoding='utf-8-sig')
    if text.lstrip().startswith('{'):
        return json.loads(text)
    match = re.search(r'<script id="catalog-data" type="application/json">(.*?)</script>', text, re.S)
    if not match:
        raise ValueError('文件不是配置合集 HTML 或配置 JSON。')
    return json.loads(match[1])


def validate_value(field, value):
    kind = field['type']
    numeric = isinstance(value, (int, float)) and not isinstance(value, bool)
    if kind == 1:
        valid = isinstance(value, bool)
    elif kind == 2:
        valid = numeric and math.isfinite(value) and int(value) == value and abs(value) <= 2147483647
    elif kind == 3:
        valid = numeric and math.isfinite(value) and abs(value) < 1e12
    elif kind in (4, 21, 22):
        valid = isinstance(value, str) and len(value) <= 10000
    elif kind == 5:
        valid = isinstance(value, list) and len(value) == 2 and all(type(x) in (int, float) and math.isfinite(x) for x in value)
    elif kind == 28:
        valid = isinstance(value, list) and len(value) <= 256
        if valid:
            for item in value:
                validate_value({'type': field['array_type'], 'name': field['name'], 'hint': 0}, item)
    else:
        valid = False
    if not valid:
        raise ValueError(field['name'] + '：数据类型或数值不合法。')
    if field['hint'] == 2 and kind == 2:
        choices, number = [], -1
        for option in field['hint_string'].split(','):
            if ':' in option:
                number = int(option.rsplit(':', 1)[1])
            else:
                number += 1
            choices.append(number)
        if value not in choices:
            raise ValueError(field['name'] + '：枚举选项无效。')
    if field['hint'] == 1 and numeric:
        parts = field['hint_string'].split(',')
        if len(parts) >= 2 and not float(parts[0]) <= value <= float(parts[1]):
            raise ValueError(field['name'] + '：超出 Inspector 允许范围 ' + ','.join(parts[:2]))
    positive = {'max_hp', 'cooldown', 'interval', 'duration', 'cast_delay', 'dash_speed', 'lasting_rounds', 'draw_threshold', 'rounds', 'casts', 'pierce_count'}
    nonnegative = {'attack', 'defence', 'speed', 'cast_range', 'attack_rate', 'card_cost', 'radius', 'damage', 'dash_distance'}
    if numeric and (field['name'] in positive and value <= 0 or field['name'] in nonnegative and value < 0):
        raise ValueError(field['name'] + '：数值必须为正数或非负数。')
    if field['name'] == 'dodge_rate' and not 0 <= value <= 1:
        raise ValueError('闪避率必须为 0～1。')
    if field['name'] == 'unit_team' and value not in ('team_a', 'team_b'):
        raise ValueError('阵营只能填写 team_a 或 team_b。')
    if field['name'] == 'hit_frame' and kind == 28 and any(x < 0 for x in value):
        raise ValueError('命中帧不能为负数。')
    if field['name'] == 'unlock_upgrade_levels' and kind == 28 and any(not 0 <= x <= 99 for x in value):
        raise ValueError('unlock_upgrade_levels：解锁强化等级必须为 0～99 的整数数组。')


def serialize(field, value):
    kind = field['type']
    if kind == 1:
        return 'true' if value else 'false'
    if kind == 2:
        return str(int(value))
    if kind == 3:
        return repr(float(value))
    if kind in (4, 21, 22):
        string = json.dumps(value, ensure_ascii=False)
        return ('&' + string) if kind == 21 else ('NodePath(' + string + ')') if kind == 22 else string
    if kind == 5:
        return 'Vector2(' + ', '.join(str(x) for x in value) + ')'
    if kind == 28:
        name = {2: 'int', 3: 'float', 4: 'String'}[field['array_type']]
        items = ', '.join(serialize({'type': field['array_type']}, x) for x in value)
        return 'Array[' + name + ']([' + items + '])'
    raise ValueError('不支持此字段类型')


def replace_property(text, resource_id, name, expression):
    """Touch only one property; preserve unrelated resources, images, UIDs and layout."""
    sub = resource_id.split('::', 1)[1] if '::' in resource_id else None
    header = r'^\[sub_resource [^\n]*\bid="' + re.escape(sub) + r'"[^\n]*\](?=\r?$)' if sub else r'^\[resource\](?=\r?$)'
    found = re.search(header, text, re.M)
    if not found:
        raise ValueError('找不到资源段：' + resource_id)
    start = found.end()
    following = re.search(r'^\[\w', text[start:], re.M)
    end = start + following.start() if following else len(text)
    block = text[start:end]
    assignment = re.search(r'^' + re.escape(name) + r'\s*=\s*', block, re.M)
    newline = '\r\n' if '\r\n' in text else '\n'
    if not assignment:
        script = re.search(r'^script = [^\r\n]*(?:\r?\n|$)', block, re.M)
        if not script:
            raise ValueError('资源段缺少脚本引用：' + resource_id)
        block = block[:script.end()] + name + ' = ' + expression + newline + block[script.end():]
    else:
        # Strings can contain literal newlines. Arrays may also span multiple lines.
        cursor = assignment.end()
        quote, escaped, depth = False, False, 0
        while cursor < len(block):
            char = block[cursor]
            if quote:
                if escaped:
                    escaped = False
                elif char == '\\':
                    escaped = True
                elif char == '"':
                    quote = False
            elif char == '"':
                quote = True
            elif char in '([':
                depth += 1
            elif char in ')]':
                depth -= 1
            elif char in '\r\n' and depth == 0:
                break
            cursor += 1
        block = block[:assignment.start()] + name + ' = ' + expression + block[cursor:]
    return text[:start] + block + text[end:]


def pending_columns(document, current):
    existing = {row['id']: row for row in current['records']}
    selected = []
    unique = set()
    for raw in document.get('pending_columns', []):
        if not isinstance(raw, dict):
            raise ValueError('新增字段格式无效。')
        family, name, dtype = raw.get('family'), raw.get('name'), raw.get('dtype')
        if family not in FAMILIES or dtype not in NEW_TYPES or not isinstance(name, str) or not re.fullmatch(r'[a-z][a-z0-9_]{1,49}', name):
            raise ValueError('新增字段需选择有效类别、类型和英文 snake_case 名称（2～50 字符）。')
        if (family, name) in unique:
            raise ValueError('重复新增字段：' + name)
        unique.add((family, name))
        label, note = raw.get('label'), raw.get('description', '')
        if not isinstance(label, str) or not label.strip() or len(label) > 80 or not isinstance(note, str) or len(note) > 200:
            raise ValueError('字段中文名称或说明长度无效。')
        definition = {'name': name, 'type': NEW_TYPES[dtype][0], 'hint': 0}
        validate_value(definition, raw.get('default'))
        members = [row for row in existing.values() if family_of(row) == family]
        if not members or any(any(f['name'] == name for f in row['fields']) for row in members):
            raise ValueError('字段名已存在，或此类别没有配置：' + name)
        selected.append({'family': family, 'name': name, 'dtype': dtype,
                         'label': label.strip(), 'description': note.strip(), 'default': raw['default']})
    return selected


def add_script_field(text, column):
    name, dtype = column['name'], NEW_TYPES[column['dtype']][1]
    initial = serialize({'type': NEW_TYPES[column['dtype']][0]}, column['default'])
    note = (column['label'] + '。' + column['description']).replace('\n', ' ').replace('\r', ' ')
    line = ('## 策划扩展字段“' + note + '”在 Inspector 中保存和调整；'
            '游戏玩法只有读取此字段后才会使用它。\n'
            '@export var ' + name + ': ' + dtype + ' = ' + initial + '\n\n')
    newline = '\r\n' if '\r\n' in text else '\n'
    line = line.replace('\n', newline)
    marker = re.search(r'^func\s+', text, re.M)
    position = marker.start() if marker else len(text)
    if marker:
        # Keep the existing Chinese function comment directly above its function.
        previous = list(re.finditer(r'^.*(?:\r?\n|$)', text[:position], re.M))
        for match in reversed(previous):
            if match.start() == match.end():
                continue
            content = match.group().strip()
            if content == '' or content.startswith('#'):
                position = match.start()
            else:
                break
    if '@export_group("配置表扩展字段")' not in text:
        line = '@export_group("配置表扩展字段")' + newline + line
    return text[:position] + line + text[position:]


def pending_rows(document, current, root):
    trusted = {row['id']: row for row in current['records']}
    incoming = {row.get('id'): row for row in document.get('records', []) if isinstance(row, dict)}
    selected, used = [], set()
    for raw in document.get('pending_rows', []):
        if not isinstance(raw, dict):
            raise ValueError('新增配置行格式无效。')
        source, resource_id, family = raw.get('source'), raw.get('id'), raw.get('family')
        template, row = trusted.get(source), incoming.get(resource_id)
        if not template or not row or family != family_of(template) or resource_id in used or resource_id in trusted:
            raise ValueError('新增配置行的模板、类别或目标重复：' + str(resource_id))
        used.add(resource_id)
        if family == 'card_effects':
            owner = source.split('::')[0]
            name = resource_id.removeprefix(owner + '::') if isinstance(resource_id, str) else ''
            if not resource_id.startswith(owner + '::') or not re.fullmatch(r'Resource_[a-z][a-z0-9_]{1,49}', name):
                raise ValueError('新卡牌效果必须属于模板所在卡牌，并使用有效英文标识。')
            target_file = owner.removeprefix('res://')
        else:
            slug = resource_id.removeprefix('res://data/' + family + '/') if isinstance(resource_id, str) else ''
            if not re.fullmatch(r'[a-z][a-z0-9_]{1,49}\.tres', slug) or resource_id != 'res://data/' + family + '/' + slug:
                raise ValueError('新增配置行路径无效，请使用 2～50 位英文 snake_case 标识。')
            target_file = resource_id.removeprefix('res://')
            if (root / target_file).exists():
                raise ValueError('目标资源已存在：' + resource_id)
            if family == 'units':
                source_scene = root / 'scenes/units' / (Path(source).stem + '.tscn')
                target_scene = root / 'scenes/units' / (Path(slug).stem + '.tscn')
                if not source_scene.exists() or target_scene.exists():
                    raise ValueError('单位模板场景不存在，或新单位场景已存在：' + str(target_scene))
        if row.get('script') != template['script'] or row.get('group') != template['group']:
            raise ValueError('新增配置行类型与模板不一致：' + resource_id)
        selected.append((raw, template, row, target_file))
    return selected


def copy_effect(text, source_id, new_id):
    old = source_id.split('::', 1)[1]
    new = new_id.split('::', 1)[1]
    pattern = r'^\[sub_resource [^\n]*\bid="' + re.escape(old) + r'"[^\n]*\]\r?\n(?:.*?)(?=^\[\w|\Z)'
    match = re.search(pattern, text, re.M | re.S)
    if not match or re.search(r'^\[sub_resource [^\n]*\bid="' + re.escape(new) + r'"', text, re.M):
        raise ValueError('卡牌效果模板不存在，或新效果标识已存在。')
    block = match.group().replace('id="' + old + '"', 'id="' + new + '"', 1)
    position = re.search(r'^\[resource\]', text, re.M)
    if not position:
        raise ValueError('卡牌资源段不存在。')
    text = text[:position.start()] + block + text[position.start():]
    effect_line = re.search(r'^effects\s*=\s*([^\r\n]+)', text[position.start() + len(block):], re.M)
    if not effect_line:
        raise ValueError('卡牌效果列表不存在。')
    current = effect_line.group(1)
    if not current.endswith('])'):
        raise ValueError('卡牌效果列表格式不支持新增行。')
    appended = current[:-2] + (', ' if 'SubResource(' in current else '') + 'SubResource("' + new + '")])'
    text = replace_property(text, source_id.split('::')[0], 'effects', appended)
    return re.sub(r'^(\[gd_resource [^\n]*\bload_steps=)(\d+)',
                  lambda match: match.group(1) + str(int(match.group(2)) + 1), text, count=1, flags=re.M)


def same_value(left, right):
    # Python considers True == 1; a boolean must still reach integer validation.
    if isinstance(left, bool) or isinstance(right, bool):
        return type(left) is type(right) and left == right
    if isinstance(left, list) and isinstance(right, list):
        return len(left) == len(right) and all(same_value(a, b) for a, b in zip(left, right))
    return left == right


def plan(document, current, root=ROOT):
    if document.get('format') != FORMAT:
        raise ValueError('合集版本不支持。')
    if document.get('editor_inputs'):
        raise ValueError('Godot 配置面板还有未通过解析的输入，请先修正红色格子。')
    trusted = {row['id']: row for row in current['records']}
    changes, files, seen = [], {}, set()
    columns = pending_columns(document, current)
    rows = pending_rows(document, current, root)
    new_row_ids = {raw['id'] for raw, _, _, _ in rows}
    new_names = {(c['family'], c['name']): c for c in columns}
    incoming = {row['id']: {f['name']: f for f in row.get('fields', [])}
                for row in document.get('records', []) if isinstance(row, dict) and isinstance(row.get('fields'), list)}
    for row in document.get('records', []):
        if row['id'] in new_row_ids:
            continue
        for field in row.get('fields', []):
            actual = trusted.get(row['id'])
            if actual and (family_of(actual), field['name']) in new_names:
                continue
            if same_value(field.get('value'), field.get('base')):
                continue
            pair = (row['id'], field['name'])
            if pair in seen:
                raise ValueError('重复字段：' + str(pair))
            seen.add(pair)
            spec = next((x for x in actual['fields'] if x['name'] == field['name']), None) if actual else None
            if not spec or not spec['editable']:
                raise ValueError('不可修改的资源或字段：' + str(pair))
            if not same_value(spec['value'], field.get('base')):
                raise ValueError('配置冲突：' + row['id'] + ' / ' + field['name'] + ' 已在游戏中改变。请先保存草稿，再重新导出。')
            validate_value(spec, field['value'])
            relative = actual['file'].removeprefix('res://')
            target = (root / relative).resolve()
            if not target.is_relative_to((root / 'data').resolve()) or target.suffix != '.tres':
                raise ValueError('写入路径越界')
            if relative not in files:
                original = target.read_bytes()
                if hashlib.sha256(original).hexdigest() != current['file_hashes'].get(relative):
                    raise ValueError('校验期间配置发生变化：' + relative)
                files[relative] = original.decode('utf-8-sig')
            files[relative] = replace_property(files[relative], row['id'], field['name'], serialize(spec, field['value']))
            changes.append({'id': row['id'], 'field': field['name'], 'before': spec['value'], 'after': field['value']})
    for column in columns:
        script_path = FAMILIES[column['family']]
        if hashlib.sha256((root / script_path).read_bytes()).hexdigest() != current['file_hashes'].get(script_path):
            raise ValueError('字段定义脚本已被外部修改：' + script_path)
        source = files.get(script_path, (root / script_path).read_text(encoding='utf-8-sig'))
        files[script_path] = add_script_field(source, column)
        changes.append({'id': 'res://' + script_path, 'field': column['name'], 'before': None, 'after': column['dtype'], 'schema': True, 'family': column['family']})
        for row in trusted.values():
            if family_of(row) != column['family']:
                continue
            raw = incoming.get(row['id'], {}).get(column['name'])
            field_type = NEW_TYPES[column['dtype']][0]
            new_value = column['default'] if raw is None else raw.get('value')
            validate_value({'name': column['name'], 'type': field_type, 'hint': 0}, new_value)
            relative = row['file'].removeprefix('res://')
            if relative not in files:
                original = (root / relative).read_bytes()
                if hashlib.sha256(original).hexdigest() != current['file_hashes'].get(relative):
                    raise ValueError('校验期间配置发生变化：' + relative)
                files[relative] = original.decode('utf-8-sig')
            files[relative] = replace_property(files[relative], row['id'], column['name'], serialize({'type': field_type}, new_value))
            changes.append({'id': row['id'], 'field': column['name'], 'before': None, 'after': new_value})
    if columns:
        relative = CUSTOM_FIELDS
        path = root / relative
        prior = json.loads(path.read_text(encoding='utf-8')) if path.exists() else []
        files[relative] = json.dumps(prior + columns, ensure_ascii=False, indent=2) + '\n'
    for raw, template, row, relative in rows:
        resource_id, source_id = raw['id'], raw['source']
        source_relative = template['file'].removeprefix('res://')
        source_bytes = (root / source_relative).read_bytes()
        if hashlib.sha256(source_bytes).hexdigest() != current['file_hashes'].get(source_relative):
            raise ValueError('模板在校验期间被修改：' + source_relative)
        incoming_fields = {field['name']: field for field in row['fields']}
        if raw['family'] == 'card_effects':
            if relative not in files:
                files[relative] = source_bytes.decode('utf-8-sig')
            files[relative] = copy_effect(files[relative], source_id, resource_id)
        else:
            cloned = re.sub(r' uid="uid://[^"]+"', '', source_bytes.decode('utf-8-sig'), count=1)
            cloned = re.sub(r'^metadata/_data_table_id\s*=.*(?:\r?\n|$)', '', cloned, flags=re.M)
            files[relative] = cloned
        changes.append({'id': resource_id, 'field': '__row', 'before': None, 'after': resource_id, 'row': True})
        for spec in template['fields']:
            name = spec['name']
            field = incoming_fields.get(name)
            value = spec['value'] if field is None else field.get('value')
            if name in ('unit_english_name', 'id') and raw['family'] != 'card_effects':
                value = Path(relative).stem
            if not spec['editable'] and name not in ('unit_english_name', 'id'):
                if not values_equal(value, spec['value']):
                    raise ValueError('新增配置行不能改动关联资源：' + name)
                continue
            validate_value(spec, value)
            if not values_equal(value, spec['value']) or name in ('unit_english_name', 'id'):
                files[relative] = replace_property(files[relative], resource_id, name, serialize(spec, value))
            changes.append({'id': resource_id, 'field': name, 'before': None, 'after': value})
        for column in columns:
            if column['family'] != raw['family']:
                continue
            new_value = incoming_fields.get(column['name'], {}).get('value', column['default'])
            spec = {'name': column['name'], 'type': NEW_TYPES[column['dtype']][0], 'hint': 0}
            validate_value(spec, new_value)
            files[relative] = replace_property(files[relative], resource_id, column['name'], serialize(spec, new_value))
            changes.append({'id': resource_id, 'field': column['name'], 'before': None, 'after': new_value})
        if raw['family'] == 'units':
            old_scene = 'scenes/units/' + Path(source_relative).stem + '.tscn'
            new_scene = 'scenes/units/' + Path(relative).stem + '.tscn'
            scene_bytes = (root / old_scene).read_bytes()
            if hashlib.sha256(scene_bytes).hexdigest() != current['file_hashes'].get(old_scene):
                raise ValueError('单位模板场景在校验期间被修改：' + old_scene)
            scene = re.sub(r' uid="uid://[^"]+"', '', scene_bytes.decode('utf-8-sig'), count=1)
            old_path = 'path="' + source_id + '"'
            if old_path not in scene:
                raise ValueError('单位模板场景未引用其单位数据：' + old_scene)
            scene = re.sub(r'\[ext_resource [^\n]*' + re.escape(old_path) + r'[^\n]*\]',
                           lambda match: re.sub(r' uid="uid://[^"]+"', '', match.group()).replace(old_path, 'path="' + resource_id + '"'), scene, count=1)
            files[new_scene] = scene
    proposed = {key: {f['name']: f['value'] for f in row['fields']} for key, row in trusted.items()}
    proposed.update({raw['id']: {f['name']: f['value'] for f in template['fields']}
                     for raw, template, _, _ in rows})
    definitions = dict(trusted)
    definitions.update({raw['id']: template for raw, template, _, _ in rows})
    for change in changes:
        if change.get('schema') or change['id'] not in proposed:
            continue
        proposed[change['id']][change['field']] = change['after']
    for change in changes:
        key, name = change['id'], change['field']
        if change.get('schema') or change.get('row') or key not in proposed:
            continue
        values = proposed[key]
        if name in ('hit_frame', 'cast_animation'):
            for binding in current.get('bindings', []):
                if key not in binding['skills']:
                    continue
                animation = binding['animations'].get(values['cast_animation'])
                if not animation or animation['loop']:
                    raise ValueError(binding['scene'] + '：施法动画不存在或设置了循环。')
                if any(frame >= animation['frames'] for frame in values['hit_frame']):
                    raise ValueError(binding['scene'] + '：命中帧超出动画长度。')
        if definitions[key]['script'].endswith('/card_effect.gd'):
            if values['kind'] in (7, 8) and values['lifetime'] == 2:
                raise ValueError('地面区域目前不支持“本局持续”，请选本场或指定回合。')
            if values['kind'] in (20, 21, 22, 23):
                if values['lifetime'] != 1 or values['lasting_rounds'] != 1:
                    raise ValueError('虚弱、易伤、恐吓和麻痹只持续当前回合，请设为指定回合、1 回合。')
            elif values['kind'] not in (0, 2, 3, 4, 7, 8, 18) and values['lifetime'] != 0:
                raise ValueError('一次性卡牌效果的持续类型必须为“本场战斗”。')
            if values['kind'] == 16:
                raise ValueError('自定义效果需要先添加实现脚本，不能仅切换枚举。')
            if values['kind'] in (1, 8) and not 0 < values['amount'] <= 100:
                raise ValueError('治疗或减速百分数必须大于 0 且不超过 100。')
            if values['kind'] not in (5, 6, 15, 10, 19) and values['amount'] <= 0:
                raise ValueError('此卡牌效果的数值必须大于零。')
            if values['kind'] not in (5, 1, 8, 6, 15, 10, 21, 23, 25, 28) and values['amount'] != int(values['amount']):
                raise ValueError('卡牌点数、层数和张数必须填写整数。')
            if values['kind'] == 19 and values['amount'] < 0:
                raise ValueError('阵亡加费不能为负数。')
            if values['kind'] == 23 and values['interval'] <= values['amount']:
                raise ValueError('麻痹触发间隔必须大于眩晕时长。')
            if values['kind'] == 25 and (values['crowded_unit_count'] < 2 or not 0 <= values['crowded_stat_percent'] <= 100
                                         or values['solo_attack_bonus_percent'] < 0 or values['solo_defence_bonus_percent'] < 0
                                         or not 0 <= values['cooldown_reduction_percent'] < 100):
                raise ValueError('狂化阈值至少为2，拥挤攻防为0~100%，独存增幅非负，冷却减少为0~100%（不含100%）。')
            if values['kind'] == 27 and values['required_unit_types'] < 1:
                raise ValueError('合理搭配的所需兵种种类必须至少为1。')
            if values['kind'] == 28 and (values['distance_for_max_bonus'] <= 0 or not 0 <= values['minimum_attack_percent'] <= values['amount']):
                raise ValueError('保持距离的远端距离必须大于零，近身攻击百分比不能大于远端。')
        if name == 'category' and values['category'] == 0 and not values.get('summon_unit'):
            raise ValueError('征召卡需要先在 Godot 中绑定征召单位。')
    return changes, files


def apply_document(document, root=ROOT, reader=snapshot):
    current = reader(root)
    changes, files = plan(document, current, root)
    if not changes:
        return {'changes': [], 'message': '没有待应用的修改。'}, current
    backup = root / '.maintenance/config_catalog_backups' / (datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + secrets.token_hex(3))
    backup.mkdir(parents=True)
    original = {}
    for relative in files:
        path = root / relative
        original[relative] = path.read_bytes() if path.exists() else None
        digest = hashlib.sha256(original[relative]).hexdigest() if original[relative] is not None else None
        if digest != current['file_hashes'].get(relative):
            raise ValueError('备份前配置发生变化：' + relative)
        saved = backup / relative
        saved.parent.mkdir(parents=True, exist_ok=True)
        if original[relative] is not None:
            saved.write_bytes(original[relative])
    (backup / 'changes.json').write_text(json.dumps(changes, ensure_ascii=False, indent=2), encoding='utf-8')
    try:
        for relative, content in files.items():
            # Refuse a concurrent editor save that arrived after validation.
            current_bytes = (root / relative).read_bytes() if (root / relative).exists() else None
            if current_bytes != original[relative]:
                raise ValueError('写入期间配置被其它程序修改：' + relative)
            (root / relative).parent.mkdir(parents=True, exist_ok=True)
            (root / relative).write_bytes(content.encode('utf-8'))
        verified = reader(root)
        index = {row['id']: {f['name']: f['value'] for f in row['fields']} for row in verified['records']}
        for change in changes:
            if change.get('schema'):
                if not any(c['name'] == change['field'] and c['family'] == change['family'] for c in verified['custom_columns']):
                    raise ValueError('新字段定义回读失败：' + change['field'])
                continue
            if change.get('row'):
                if change['id'] not in index:
                    raise ValueError('新配置行未被引擎读取：' + change['id'])
                continue
            if not values_equal(index.get(change['id'], {}).get(change['field']), change['after']):
                raise ValueError('引擎回读结果不一致：' + change['id'] + '/' + change['field'])
    except Exception:
        for relative, content in original.items():
            # Do not overwrite an external edit if another program raced with this tool.
            if (root / relative).read_bytes() == files[relative].encode('utf-8'):
                if content is None:
                    (root / relative).unlink()
                else:
                    (root / relative).write_bytes(content)
        raise
    row_count = sum(bool(change.get('row')) for change in changes)
    return {'changes': changes, 'backup': str(backup),
            'message': f'已创建 {row_count} 行配置，应用 {len(changes) - row_count} 项字段变更，涉及 {len(files)} 个文件。重新运行场景后生效。'}, verified


def serve(port, open_browser=True, root=ROOT, ready=None):
    state = {'data': build() if root == ROOT else snapshot(root), 'token': secrets.token_urlsafe(32)}

    class Handler(BaseHTTPRequestHandler):
        def reply(self, code, body, content_type='application/json; charset=utf-8'):
            encoded = body.encode('utf-8') if isinstance(body, str) else json.dumps(body, ensure_ascii=False).encode('utf-8')
            self.send_response(code)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(encoded)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.end_headers()
            self.wfile.write(encoded)

        def valid_host(self):
            return self.headers.get('Host') == f'127.0.0.1:{self.server.server_port}'

        def do_GET(self):
            if not self.valid_host():
                return self.reply(403, {'error': '无效的本地地址'})
            if self.path == '/':
                return self.reply(200, html_text(state['data']), 'text/html; charset=utf-8')
            if self.path == '/api/session':
                return self.reply(200, {'token': state['token']})
            self.reply(404, {'error': '未找到'})

        def do_POST(self):
            origin = f'http://127.0.0.1:{self.server.server_port}'
            if not self.valid_host() or self.headers.get('Origin') != origin or self.headers.get('X-Catalog-Token') != state['token']:
                return self.reply(403, {'error': '仅允许本机配置页面应用修改。'})
            try:
                length = int(self.headers.get('Content-Length', 0))
                if not 0 < length <= 5_000_000:
                    raise ValueError('请求大小无效')
                document = json.loads(self.rfile.read(length))
                if self.path == '/api/preview':
                    changes, _ = plan(document, snapshot(root), root)
                    return self.reply(200, {'changes': changes, 'message': f'校验通过，{len(changes)} 项变更待应用。'})
                if self.path == '/api/apply':
                    result, state['data'] = apply_document(document, root)
                    if root == ROOT:
                        build(state['data'])
                    return self.reply(200, {**result, 'data': state['data']})
                self.reply(404, {'error': '未找到'})
            except Exception as error:
                self.reply(400, {'error': str(error)})

    server = HTTPServer(('127.0.0.1', port), Handler)
    url = f'http://127.0.0.1:{server.server_port}'
    print('配置合集：' + url, flush=True)
    if ready:
        ready(url, server)
    if open_browser:
        webbrowser.open(url)
    server.serve_forever()


def main():
    global GODOT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['build', 'serve', 'check', 'apply', 'editor-read', 'editor-check', 'editor-apply'])
    parser.add_argument('document', nargs='?')
    parser.add_argument('--port', type=int, default=0)
    parser.add_argument('--no-browser', action='store_true')
    parser.add_argument('--result', help='Godot 编辑器桥接的 JSON 结果文件')
    parser.add_argument('--project', default=str(ROOT), help='待读取的 Godot 项目目录')
    parser.add_argument('--godot', help='当前编辑器使用的 Godot 可执行文件')
    args = parser.parse_args()
    if args.godot:
        GODOT = args.godot
    if args.command.startswith('editor-'):
        root = Path(args.project).resolve()
        try:
            if args.command == 'editor-read':
                result = {'ok': True, 'data': snapshot(root), 'message': '已读取游戏实际配置。'}
            else:
                if not args.document:
                    raise ValueError('缺少配置草稿文件。')
                document = read_document(args.document)
                if args.command == 'editor-check':
                    changes, _ = plan(document, snapshot(root), root)
                    result = {'ok': True, 'changes': changes, 'message': f'校验通过，{len(changes)} 项变更待应用。'}
                else:
                    applied, data = apply_document(document, root)
                    if root == ROOT:
                        build(data)
                    result = {'ok': True, **applied, 'data': data}
        except Exception as error:
            result = {'ok': False, 'error': str(error)}
        if args.result:
            Path(args.result).write_text(json.dumps(result, ensure_ascii=False), encoding='utf-8')
        else:
            print(json.dumps(result, ensure_ascii=False))
        return
    if args.command == 'serve':
        serve(args.port, not args.no_browser)
    elif args.command == 'build':
        data = build()
        print(f"已导出 {len(data['records'])} 个配置资源：{HTML}")
    else:
        if not args.document:
            parser.error('需要 HTML 或 JSON 文件路径')
        document = read_document(args.document)
        if args.command == 'check':
            changes, _ = plan(document, snapshot())
            print(json.dumps(changes, ensure_ascii=False, indent=2))
        else:
            result, data = apply_document(document)
            build(data)
            print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
