"""Exercise real Godot export/apply against disposable fixtures, never live balance data."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
import threading
import urllib.request
import subprocess
import sys
import catalog

SCRIPT = '''# 这玩意儿是干嘛的（核心逻辑）：提供隔离的配置写回测试样例。
# 数据是咋流动的（数据流向）：测试参数进入资源，由引擎加载核对。
# 为啥这么写（选型决策）：独立项目避免改动真实游戏数值。
# 性能咋样（复杂度）：仅自动测试时加载。
extends Resource
enum Kind { ONE, TWO }
@export var card_name: String = "默认名字"
@export_multiline var description: String = ""
## 效果基础数值。[br]由配置工具展示。
@export var amount: float = 5.0
@export var max_hp: int = 100
@export var kind: Kind = Kind.ONE
@export var hit_frame: Array[int] = [3]
@export var offset: Vector2 = Vector2(1, 2)
@export var id: StringName = &"fixture"
@export var point: NodePath = ^"Point"
@export var effects: Array[Resource] = []
'''
RESOURCE = '''[gd_resource type="Resource" load_steps=3 format=3]

[ext_resource type="Script" path="res://data/cards/card_definition.gd" id="1"]
[ext_resource type="Script" path="res://data/card_effects/card_effect.gd" id="2"]

[sub_resource type="Resource" id="Resource_effect"]
script = ExtResource("2")
description = "old
multiline"

[resource]
script = ExtResource("1")
card_name = "原名"
effects = Array[Resource]([SubResource("Resource_effect")])
'''


class CatalogTest(unittest.TestCase):
    def test_boolean_array_is_not_an_unchanged_integer_array(self):
        self.assertFalse(catalog.same_value([True], [1]))
        self.assertTrue(catalog.same_value([1.0], [1]))

    def test_parameter_descriptions(self):
        fields = {f['name']: f for f in self.base['records'][0]['fields']}
        self.assertEqual(fields['amount']['description'], '效果基础数值。\n由配置工具展示。')
        self.assertEqual(fields['max_hp']['description'], '')

    @classmethod
    def setUpClass(cls):
        cls.folder = tempfile.TemporaryDirectory(prefix='ballsprite-catalog-test-')
        cls.root = Path(cls.folder.name)
        for name in ['cards', 'card_effects', 'units', 'skills', 'relics', 'potions']:
            (cls.root / 'data' / name).mkdir(parents=True)
        (cls.root / 'scenes/units').mkdir(parents=True)
        (cls.root / 'project.godot').write_text('config_version=5\n', encoding='utf-8')
        exporter = cls.root / catalog.EXPORT_SCRIPT
        exporter.parent.mkdir(parents=True)
        exporter.write_bytes((catalog.ROOT / catalog.EXPORT_SCRIPT).read_bytes())
        help_path = Path('addons/shared/script_property_help.gd')
        (cls.root / help_path).parent.mkdir(parents=True)
        (cls.root / help_path).write_bytes((catalog.ROOT / help_path).read_bytes())
        cls.script = cls.root / 'data/cards/card_definition.gd'
        cls.script.write_text(SCRIPT, encoding='utf-8')
        (cls.root / 'data/card_effects/card_effect.gd').write_text(SCRIPT, encoding='utf-8')
        cls.path = cls.root / 'data/cards/fixture.tres'
        cls.path.write_text(RESOURCE, encoding='utf-8')
        cls.base = catalog.snapshot(cls.root)

    @classmethod
    def tearDownClass(cls):
        cls.folder.cleanup()

    def setUp(self):
        self.path.write_text(RESOURCE, encoding='utf-8')
        self.script.write_text(SCRIPT, encoding='utf-8')
        custom = self.root / catalog.CUSTOM_FIELDS
        if custom.exists():
            custom.unlink()
        self.original = self.path.read_bytes()
        self.document = copy.deepcopy(self.base)

    def edit(self, name, value, nested=False):
        row = next(r for r in self.document['records'] if ('::' in r['id']) == nested)
        field = next(f for f in row['fields'] if f['name'] == name)
        field['value'] = value

    def add_row(self, document, source, new_id, family):
        template = next(r for r in document['records'] if r['id'] == source)
        row = copy.deepcopy(template)
        row['id'] = new_id
        row['file'] = new_id.split('::')[0]
        for field in row['fields']:
            if field['name'] in ('unit_english_name', 'id'):
                field['value'] = Path(new_id.split('::')[0]).stem
        document['records'].append(row)
        document.setdefault('pending_rows', []).append({'family': family, 'source': source, 'id': new_id})
        return row

    def test_add_card_row_creates_independent_resource_and_effect(self):
        new_path = self.root / 'data/cards/new_card.tres'
        source = 'res://data/cards/fixture.tres'
        row = self.add_row(self.document, source, 'res://data/cards/new_card.tres', 'cards')
        next(f for f in row['fields'] if f['name'] == 'card_name')['value'] = '新增卡牌'
        try:
            result, fresh = catalog.apply_document(self.document, self.root)
            self.assertTrue(new_path.exists())
            self.assertIn('card_name = "新增卡牌"', new_path.read_text(encoding='utf-8'))
            self.assertIn('res://data/cards/new_card.tres::Resource_effect', [r['id'] for r in fresh['records']])
            self.assertIn('新增卡牌', [f['value'] for r in fresh['records'] if r['id'] == row['id'] for f in r['fields'] if f['name'] == 'card_name'])
            self.assertFalse((Path(result['backup']) / 'data/cards/new_card.tres').exists())
            self.assertEqual(self.path.read_text(encoding='utf-8'), RESOURCE)
        finally:
            new_path.unlink(missing_ok=True)

    def test_add_card_effect_row_appends_to_owner(self):
        source = 'res://data/cards/fixture.tres::Resource_effect'
        new_id = 'res://data/cards/fixture.tres::Resource_second'
        row = self.add_row(self.document, source, new_id, 'card_effects')
        next(f for f in row['fields'] if f['name'] == 'amount')['value'] = 12.0
        result, fresh = catalog.apply_document(self.document, self.root)
        self.assertIn('SubResource("Resource_second")', self.path.read_text(encoding='utf-8'))
        owner = next(r for r in fresh['records'] if r['id'] == source.split('::')[0])
        self.assertIn(new_id, next(f['value'] for f in owner['fields'] if f['name'] == 'effects'))
        self.assertEqual(next(f['value'] for r in fresh['records'] if r['id'] == new_id for f in r['fields'] if f['name'] == 'amount'), 12.0)
        self.assertTrue((Path(result['backup']) / 'data/cards/fixture.tres').exists())

    def test_reject_bad_new_row_path(self):
        self.add_row(self.document, 'res://data/cards/fixture.tres', 'res://data/cards/../units/unsafe.tres', 'cards')
        with self.assertRaisesRegex(ValueError, '路径无效'):
            catalog.plan(self.document, self.base, self.root)

    def test_add_row_and_column_together(self):
        new_path = self.root / 'data/cards/new_with_column.tres'
        row = self.add_row(self.document, 'res://data/cards/fixture.tres',
                           'res://data/cards/new_with_column.tres', 'cards')
        column = {'family': 'cards', 'name': 'extra_points', 'label': '额外点数',
                  'dtype': 'int', 'default': 2, 'description': ''}
        self.document['pending_columns'] = [column]
        for record in self.document['records']:
            if record['id'].endswith('::Resource_effect'):
                continue
            record['fields'].append({'name': 'extra_points', 'type': 2, 'editable': True,
                                     'value': 8 if record is row else 3, 'base': None, 'new': True})
        try:
            _, verified = catalog.apply_document(self.document, self.root)
            self.assertIn('extra_points = 8', new_path.read_text(encoding='utf-8'))
            self.assertEqual(next(f['value'] for r in verified['records'] if r['id'] == row['id']
                                  for f in r['fields'] if f['name'] == 'extra_points'), 8)
        finally:
            new_path.unlink(missing_ok=True)

    def test_new_file_is_removed_when_readback_fails(self):
        new_path = self.root / 'data/cards/rollback_card.tres'
        self.add_row(self.document, 'res://data/cards/fixture.tres',
                     'res://data/cards/rollback_card.tres', 'cards')
        calls = []
        def fail_second(root):
            calls.append(root)
            if len(calls) == 2:
                raise ValueError('readback failed')
            return self.base
        with self.assertRaisesRegex(ValueError, 'readback failed'):
            catalog.apply_document(self.document, self.root, fail_second)
        self.assertFalse(new_path.exists())

    def test_add_unit_row_creates_matching_scene(self):
        unit_script = self.root / 'data/units/unit_data.gd'
        scene_script = self.root / 'data/units/scene_root.gd'
        unit = self.root / 'data/units/fixture.tres'
        scene = self.root / 'scenes/units/fixture.tscn'
        new_unit = self.root / 'data/units/new_unit.tres'
        new_scene = self.root / 'scenes/units/new_unit.tscn'
        unit_script.write_text(SCRIPT.replace('@export var card_name: String = "默认名字"',
            '@export var unit_name: String = "样例单位"\n@export var unit_english_name: String = "fixture"\n@export var unit_team: String = "team_a"'), encoding='utf-8')
        scene_script.write_text('''# 这玩意儿是干嘛的（核心逻辑）：测试场景根节点的资源绑定。
# 数据是咋流动的（数据流向）：场景装载时注入单位资源。
# 为啥这么写（选型决策）：独立场景便于验证复制后的资源路径。
# 性能咋样（复杂度）：仅在隔离测试中使用。
extends Node2D
@export var unit_data: Resource
''', encoding='utf-8')
        unit.write_text('''[gd_resource type="Resource" format=3]
[ext_resource type="Script" path="res://data/units/unit_data.gd" id="1"]
[resource]
script = ExtResource("1")
unit_name = "样例单位"
unit_english_name = "fixture"
''', encoding='utf-8')
        scene.write_text('''[gd_scene load_steps=3 format=3]
[ext_resource type="Script" path="res://data/units/scene_root.gd" id="1"]
[ext_resource type="Resource" path="res://data/units/fixture.tres" id="2"]
[node name="Fixture" type="Node2D"]
script = ExtResource("1")
unit_data = ExtResource("2")
''', encoding='utf-8')
        try:
            document = catalog.snapshot(self.root)
            row = self.add_row(document, 'res://data/units/fixture.tres', 'res://data/units/new_unit.tres', 'units')
            next(f for f in row['fields'] if f['name'] == 'unit_name')['value'] = '新增单位'
            result, verified = catalog.apply_document(document, self.root)
            self.assertTrue(new_scene.exists())
            self.assertIn('path="res://data/units/new_unit.tres"', new_scene.read_text(encoding='utf-8'))
            self.assertEqual(next(f['value'] for r in verified['records'] if r['id'] == row['id'] for f in r['fields'] if f['name'] == 'unit_english_name'), 'new_unit')
            self.assertIn('scenes/units/new_unit.tscn', result['backup'] and verified['file_hashes'])
        finally:
            for path in (unit_script, scene_script, unit, scene, new_unit, new_scene):
                path.unlink(missing_ok=True)

    def test_real_engine_roundtrip(self):
        self.edit('card_name', '测试 "引号"\n第二行 </script>')
        self.edit('max_hp', 123)
        self.edit('amount', 9.0, True)
        self.edit('description', '新的\n多行文案', True)
        self.edit('offset', [12.3, -8])
        self.edit('point', 'Other/Point')
        self.edit('hit_frame', [1, 4, 8])
        result, exported = catalog.apply_document(self.document, self.root)
        self.assertEqual(len(result['changes']), 7)
        self.assertEqual((Path(result['backup']) / 'data/cards/fixture.tres').read_bytes(), self.original)
        self.assertEqual(catalog.plan(exported, exported, self.root)[0], [])
        self.assertIn('effects = Array[Resource]', self.path.read_text(encoding='utf-8'))

    def test_conflicts_and_bad_values_do_not_write(self):
        self.edit('max_hp', 200)
        newer = copy.deepcopy(self.base)
        next(f for r in newer['records'] if '::' not in r['id'] for f in r['fields'] if f['name']=='max_hp')['value'] = 300
        with self.assertRaisesRegex(ValueError, '冲突'):
            catalog.plan(self.document, newer, self.root)
        self.assertEqual(self.path.read_text(encoding='utf-8'), RESOURCE)
        for name, value in [('max_hp', -1), ('kind', 99), ('hit_frame', [-3]), ('amount', float('nan'))]:
            self.document = copy.deepcopy(self.base)
            self.edit(name, value)
            with self.assertRaises(ValueError):
                catalog.plan(self.document, self.base, self.root)

    def test_readonly_and_unknown_resource(self):
        self.edit('effects', [])
        with self.assertRaisesRegex(ValueError, '不可修改'):
            catalog.plan(self.document, self.base, self.root)
        self.document = copy.deepcopy(self.base)
        self.edit('max_hp', 999)
        for r in self.document['records']:
            r['id'] = 'res://../outside.tres'
        with self.assertRaises(ValueError):
            catalog.plan(self.document, self.base, self.root)

    def test_failed_readback_rolls_back(self):
        self.edit('max_hp', 201)
        calls = []
        def fail_second(root):
            calls.append(root)
            if len(calls) == 2:
                raise ValueError('readback failed')
            return self.base
        with self.assertRaisesRegex(ValueError, 'readback failed'):
            catalog.apply_document(self.document, self.root, fail_second)
        self.assertEqual(self.path.read_text(encoding='utf-8'), RESOURCE)

    def test_portable_html_and_json(self):
        self.edit('card_name', '</script><script>invalid</script>')
        html = catalog.html_text(self.document)
        path = self.root / 'portable.html'
        path.write_text(html, encoding='utf-8')
        restored = catalog.read_document(path)
        self.assertEqual(restored, self.document)
        self.assertNotIn('</script><script>invalid', html)
        path = self.root / 'portable.json'
        path.write_text(json.dumps(self.document), encoding='utf-8')
        self.assertEqual(catalog.read_document(path), self.document)

    def test_native_editor_bridge_reads_applies_and_reports_errors(self):
        result_path = self.root / 'editor_result.json'
        draft_path = self.root / 'editor_draft.json'
        def run(command):
            args = [sys.executable, str(Path(catalog.__file__)), command]
            if command != 'editor-read':
                draft_path.write_text(json.dumps(self.document), encoding='utf-8')
                args.append(str(draft_path))
            args += ['--result', str(result_path), '--project', str(self.root), '--godot', catalog.GODOT]
            process = subprocess.run(args, capture_output=True, timeout=15)
            self.assertEqual(process.returncode, 0, process.stderr)
            return json.loads(result_path.read_text(encoding='utf-8'))
        self.assertTrue(run('editor-read')['ok'])
        self.edit('card_name', '原生面板保存测试')
        preview = run('editor-check')
        self.assertTrue(preview['ok'])
        self.assertEqual(self.path.read_bytes(), self.original)
        result = run('editor-apply')
        self.assertTrue(result['ok'])
        self.assertIn('card_name = "原生面板保存测试"', self.path.read_text(encoding='utf-8'))
        self.assertTrue(Path(result['backup']).exists())
        self.document = result['data']
        self.document['editor_inputs'] = {'res://data/cards/fixture.tres|card_name': '未解析输入'}
        self.assertFalse(run('editor-apply')['ok'])
        self.document.pop('editor_inputs')
        self.edit('max_hp', -5)
        rejected = run('editor-apply')
        self.assertFalse(rejected['ok'])
        self.assertIn('max_hp', rejected['error'])

    def test_add_column_writes_schema_and_resource(self):
        column = {'family': 'cards', 'name': 'bonus_points', 'label': '奖励点数',
                  'dtype': 'int', 'default': 2, 'description': '供后续玩法读取'}
        self.document['pending_columns'] = [column]
        row = next(r for r in self.document['records'] if '::' not in r['id'])
        row['fields'].append({'name': 'bonus_points', 'type': 2, 'editable': True,
                              'value': 7, 'base': None, 'new': True})
        result, verified = catalog.apply_document(self.document, self.root)
        self.assertIn('@export var bonus_points: int = 2', self.script.read_text(encoding='utf-8'))
        self.assertIn('bonus_points = 7', self.path.read_text(encoding='utf-8'))
        value = next(f['value'] for r in verified['records'] if '::' not in r['id']
                     for f in r['fields'] if f['name'] == 'bonus_points')
        self.assertEqual(value, 7)
        self.assertEqual(verified['custom_columns'][0]['label'], '奖励点数')
        self.assertTrue((Path(result['backup']) / 'data/cards/card_definition.gd').exists())

    def test_reject_duplicate_new_column(self):
        self.document['pending_columns'] = [{'family': 'cards', 'name': 'card_name',
            'label': '重复', 'dtype': 'text', 'default': '', 'description': ''}]
        with self.assertRaisesRegex(ValueError, '已存在'):
            catalog.plan(self.document, self.base, self.root)

    def test_added_skill_field_is_inherited_by_skill_subclasses(self):
        base = self.root / 'data/skills/skill_base.gd'
        subclass = self.root / 'data/skills/fake_skill.gd'
        resource = self.root / 'data/skills/fake_skill.tres'
        base.write_text(SCRIPT.replace('extends Resource', 'extends Resource\n@export var skill_name: String = "测试技能"'), encoding='utf-8')
        subclass.write_text('''# 这玩意儿是干嘛的（核心逻辑）：测试技能继承。
# 数据是咋流动的（数据流向）：基础字段传到技能子类。
# 为啥这么写（选型决策）：模拟游戏里的技能结构。
# 性能咋样（复杂度）：只在测试时使用。
extends "res://data/skills/skill_base.gd"
@export var special: int = 2
''', encoding='utf-8')
        resource.write_text('''[gd_resource type="Resource" format=3]
[ext_resource type="Script" path="res://data/skills/fake_skill.gd" id="1"]
[resource]
script = ExtResource("1")
''', encoding='utf-8')
        try:
            document = catalog.snapshot(self.root)
            record = next(r for r in document['records'] if r['id'].endswith('/fake_skill.tres'))
            self.assertTrue(any(f['name'] == 'skill_name' for f in record['fields']))
            document['pending_columns'] = [{'family': 'skills', 'name': 'impact_score',
                'label': '影响值', 'dtype': 'int', 'default': 1, 'description': ''}]
            result, fresh = catalog.apply_document(document, self.root)
            value = next(f['value'] for r in fresh['records'] if r['id'] == record['id']
                         for f in r['fields'] if f['name'] == 'impact_score')
            self.assertEqual(value, 1)
            self.assertIn('@export var impact_score: int = 1', base.read_text(encoding='utf-8'))
            self.assertIn('impact_score = 1', resource.read_text(encoding='utf-8'))
        finally:
            base.unlink(missing_ok=True)
            subclass.unlink(missing_ok=True)
            resource.unlink(missing_ok=True)

    def test_skill_unlock_levels_save_inherited_array_and_enforce_range(self):
        base = self.root / 'data/skills/skill_base.gd'
        subclass = self.root / 'data/skills/unlock_skill.gd'
        resource = self.root / 'data/skills/unlock_skill.tres'
        base.write_text('extends Resource\n@export var unlock_upgrade_levels: Array[int] = [0, 1]\n', encoding='utf-8')
        subclass.write_text('extends "res://data/skills/skill_base.gd"\n', encoding='utf-8')
        resource.write_text('''[gd_resource type="Resource" format=3]
[ext_resource type="Script" path="res://data/skills/unlock_skill.gd" id="1"]
[resource]
script = ExtResource("1")
''', encoding='utf-8')
        try:
            document = catalog.snapshot(self.root)
            row = next(r for r in document['records'] if r['id'].endswith('/unlock_skill.tres'))
            field = next(f for f in row['fields'] if f['name'] == 'unlock_upgrade_levels')
            self.assertEqual(field['value'], [0, 1])
            self.assertTrue(field['editable'])
            field['value'] = [0, 2]
            result, fresh = catalog.apply_document(document, self.root)
            self.assertIn('unlock_upgrade_levels = Array[int]([0, 2])', resource.read_text(encoding='utf-8'))
            saved_row = next(r for r in fresh['records'] if r['id'] == row['id'])
            saved = next(f for f in saved_row['fields'] if f['name'] == 'unlock_upgrade_levels')
            self.assertEqual(saved['value'], [0, 2])
            self.assertTrue((Path(result['backup']) / 'data/skills/unlock_skill.tres').exists())
            for invalid in (-1, [-1], [100], [1.5], [True], ['1'], {'level': 1}):
                saved['value'] = invalid
                with self.assertRaisesRegex(ValueError, 'unlock_upgrade_levels'):
                    catalog.plan(fresh, catalog.snapshot(self.root), self.root)
            self.assertIn('unlock_upgrade_levels = Array[int]([0, 2])', resource.read_text(encoding='utf-8'))
            saved['value'] = []
            _, empty = catalog.apply_document(fresh, self.root)
            empty_row = next(r for r in empty['records'] if r['id'] == row['id'])
            self.assertEqual(next(f['value'] for f in empty_row['fields'] if f['name'] == 'unlock_upgrade_levels'), [])
            self.assertIn('unlock_upgrade_levels = Array[int]([])', resource.read_text(encoding='utf-8'))
        finally:
            base.unlink(missing_ok=True)
            subclass.unlink(missing_ok=True)
            resource.unlink(missing_ok=True)

    def test_local_apply_button_adds_column_end_to_end(self):
        opened = threading.Event()
        state = {}
        def ready(url, server):
            state.update(url=url, server=server)
            opened.set()
        worker = threading.Thread(target=catalog.serve, args=(0, False, self.root, ready), daemon=True)
        worker.start()
        self.assertTrue(opened.wait(5))
        try:
            url = state['url']
            html = urllib.request.urlopen(url, timeout=5).read().decode('utf-8')
            self.assertIn('新增字段列', html)
            token = json.load(urllib.request.urlopen(url + '/api/session', timeout=5))['token']
            document = copy.deepcopy(self.base)
            document['pending_columns'] = [{'family': 'cards', 'name': 'critical_bonus',
                'label': '暴击加成', 'dtype': 'float', 'default': 0.0, 'description': '测试配置'}]
            row = next(r for r in document['records'] if '::' not in r['id'])
            row['fields'].append({'name': 'critical_bonus', 'type': 3, 'editable': True,
                'value': 0.25, 'base': None, 'new': True})
            def post(endpoint):
                request = urllib.request.Request(url + endpoint, data=json.dumps(document).encode(),
                    headers={'Content-Type': 'application/json', 'Origin': url, 'X-Catalog-Token': token})
                return json.load(urllib.request.urlopen(request, timeout=10))
            self.assertGreater(len(post('/api/preview')['changes']), 0)
            result = post('/api/apply')
            self.assertIn('critical_bonus = 0.25', self.path.read_text(encoding='utf-8'))
            self.assertEqual(result['data']['custom_columns'][0]['label'], '暴击加成')
            self.assertEqual(result['data']['pending_columns'], [])
        finally:
            state['server'].shutdown()
            worker.join(5)
            state['server'].server_close()


if __name__ == '__main__':
    unittest.main(verbosity=2)
