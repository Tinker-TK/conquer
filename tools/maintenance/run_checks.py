"""Run real headless regressions, requiring completion markers and clean engine logs."""
from pathlib import Path
import argparse
import json
import math
import os
import re
import uuid

try:
    from .godot_process import is_engine_error, run_guarded
except ImportError:
    from godot_process import is_engine_error, run_guarded


RUNNER = 'tests/card_framework_test_runner.gd'
REGRESSIONS = {
    'balance-framework': ('balance-framework', r'BALANCE_FRAMEWORK_TEST: \d+ checks; failures=\[\]'),
    'balance-ui': ('balance-ui', r'BALANCE_UI_TEST: \d+ checks; failures=\[\]'),
    'relics': ('relics', r'RELICS_TEST: \d+ checks; failures=\[\]'),
    'potion-catalog': ('potion-catalog', r'POTION_CATALOG_TEST: \d+ checks; failures=\[\]'),
    'potion-effects': ('potion-effects', r'POTION_EFFECTS_TEST: \d+ checks; failures=\[\]'),
    'expanded-cards': ('expanded-cards', r'EXPANDED_CARDS_TEST: \d+ checks; failures=\[\]'),
    'card-enhancement': ('card-enhancement', r'CARD_ENHANCEMENT_TEST: \d+ checks; failures=\[\]'),
    'stair-displacement': ('stair-displacement', r'STAIR_DISPLACEMENT_TEST: \d+ checks; failures=\[\]'),
    'combat-numbers': ('combat-numbers', r'COMBAT_NUMBERS_TEST: \d+ checks; failures=\[\]'),
    'status-effects': ('status-effects', r'UNIT_STATUS_EFFECTS_TEST: \d+ checks; failures=\[\]'),
    'strategy-cards': ('strategy-cards', r'STRATEGY_CARDS_TEST: \d+ checks; failures=\[\]'),
    'card-description': ('card-description', r'CARD_DESCRIPTION_TEST: \d+ checks; failures=\[\]'),
    'flying': ('flying', r'FLYING_UNITS_TEST: \d+ checks; failures=\[\]'),
    'enemy-only': ('enemy-only', r'ENEMY_ONLY_UNITS_TEST: \d+ checks; failures=\[\]'),
    'deployment-floors': ('deployment-floors', r'DEPLOYMENT_FLOORS_TEST: \d+ checks; failures=\[\]'),
    'floors': ('floors', r'BATTLE_FLOORS_TEST: \d+ checks, 0 failures'),
    'stair-crowd': ('stair-crowd', r'STAIR_CROWD_TEST: \d+ checks; failures=\[\]'),
    'enemy-pack': ('enemy-pack', r'ENEMY_PACK_TEST: \d+ checks; failures=\[\]'),
    'were-wolf-skills': ('were-wolf-skills', r'WERE_WOLF_SKILLS_TEST: \d+ checks; failures=\[\]'),
    'wolf-pounce': ('wolf-pounce', r'WOLF_POUNCE_TEST: \d+ checks; failures=\[\]'),
    'consecutive-attack': ('consecutive-attack', r'CONSECUTIVE_ATTACK_TEST: \d+ checks; failures=\[\]'),
    'protection-aura': ('protection-aura', r'PROTECTION_AURA_TEST: \d+ checks; failures=\[\]'),
    'knight-draw': ('knight-draw', r'KNIGHT_DEPLOYMENT_DRAW_TEST: \d+ checks; failures=\[\]'),
    'knight-blood': ('knight-blood', r'KNIGHT_BLOOD_TEST: \d+ checks; failures=\[\]'),
    'templar-taunt': ('templar-taunt', r'TEMPLAR_TAUNT_TEST: \d+ checks; failures=\[\]'),
    'cavalry-charge': ('cavalry-charge', r'CAVALRY_CHARGE_TEST: \d+ checks; failures=\[\]'),
    'sword-wind': ('sword-wind', r'SWORD_WIND_TEST: \d+ checks; failures=\[\]'),
    'bear-leap-chain': ('bear-leap-chain', r'BEAR_LEAP_CHAIN_TEST: \d+ checks; failures=\[\]'),
    'sword-arrow': ('sword-arrow', r'SWORD_ARROW_TEST: \d+ checks; failures=\[\]'),
    'skill-unlock': ('skill-unlock', 'SKILL_UNLOCK_PASS'),
    'card-unit-details': ('card-unit-details', r'CARD_UNIT_DETAILS_TEST: \d+ checks; failures=\[\]'),
    'battle-speed': ('battle-speed', r'BATTLE_SPEED_TEST: \d+ checks; failures=\[\]'),
    'combat-audio': ('combat-audio', r'COMBAT_AUDIO_TEST: \d+ checks; PASS'),
    'level-spawn': ('level-spawn', r'LEVEL_SPAWN_TEST: \d+ checks; \d+ levels; \d+ scenes; \d+ waves; \d+ rounds; PASS'),
    'tactical-cards': ('tactical-cards', r'TACTICAL_CARDS_TEST: \d+ checks; failures=\[\]'),
    'battle-rewards': ('battle-rewards', 'BATTLE_REWARDS_PASS'),
    'cards': ('', 'CARD_FRAMEWORK_SMOKE_PASS'),
    'skeleton-archer': ('skeleton-archer', 'SKELETON_ARCHER_ATTACK_PASS'),
    'wizard-fire-ball': ('wizard-fire-ball', 'WIZARD_FIRE_BALL_PASS'),
    'wizard-frost-storm': ('wizard-frost-storm', r'WIZARD_FROST_STORM_TEST: \d+ checks; failures=\[\]'),
    'priest-chant-shield': ('priest-chant-shield', r'PRIEST_CHANT_SHIELD_TEST: \d+ checks; failures=\[\]'),
    'monster-test-priest': ('monster-test-priest', r'MONSTER_TEST_PRIEST_TEST: \d+ checks; failures=\[\]'),
    'archer-piercing': ('archer-piercing', r'ARCHER_PIERCING_TEST: \d+ checks; failures=\[\]'),
    'soldier-branches': ('soldier-branches', r'SOLDIER_BRANCHES_TEST: \d+ checks; failures=\[\]'),
    'armored-axeman': ('armored-axeman', r'ARMORED_AXEMAN_TEST: \d+ checks; failures=\[\]'),
    'counter': ('counter', 'COUNTER_ATTACK_PASS'),
    'monster-test': ('monster-test', 'MONSTER_TEST_SCENE_PASS'),
    'bloodthirst': ('bloodthirst', 'BLOODTHIRST_ATTACK_PASS'),
    'targeting': ('targeting', 'SKILL_TARGETING_PASS'),
    'targeting-navigation': ('targeting-navigation', 'ENEMY_TARGETING_NAVIGATION_PASS'),
    'summon': ('summon', 'SUMMON_SKILL_TEST_OK'),
    'battle': ('battle-architecture', 'BATTLE_ARCHITECTURE_PASS'),
    'camera': ('camera', 'BATTLE_CAMERA_PASS'),
    'pointer': ('pointer', r'POINTER_INTERACTION_TEST: \d+ checks; failures=\[\]'),
    'pile-view': ('pile-view', 'PILE_VIEW_PASS'),
    'movement': ('movement', 'NAVIGATION_MOVEMENT_PASS'),
    'items': ('items', 'RUN_ITEMS_PASS'),
    'potion-visuals': ('potion-visuals', r'POTION_VISUALS_TEST: \d+ checks; failures=\[\]'),
    'thunder-cloud-potion': ('thunder-cloud-potion', r'THUNDER_CLOUD_POTION_TEST: \d+ checks; failures=\[\]'),
    'items-ui': ('items-ui', 'RUN_ITEMS_UI_PASS'),
    'navigation-deploy': ('navigation-deploy', 'NAVIGATION_DEPLOYMENT_PASS'),
    'energy': ('energy', 'ENERGY_OVERFLOW_PASS'),
    'random-draw': ('random-draw', 'RANDOM_DRAW_PLAY_PASS'),
    'level': ('level', 'LEVEL_TEMPLATE_PASS'),
    'zone': ('zone', 'ZONE_LIFETIMES_PASS'),
    'buff': ('buff', 'BUFF_LIFETIMES_PASS'),
    'inspector': ('inspector', 'UNIT_INSPECTOR_PASS'),
    'unit-details': ('unit-details', r'UNIT_DETAILS_TEST: \d+ checks; failures=\[\]'),
    'new-unit': ('new-unit', 'NEW_UNIT_ENHANCEMENT_LOGIC_PASS'),
    'round': ('round', 'ENHANCED_UNIT_NEXT_ROUND_PASS'),
    'card-cost': ('card-cost', 'CARD_COST_INCREASE_PASS'),
    'undying-army': ('undying-army', 'UNDYING_ARMY_PASS'),
    'card-motion': ('card-motion', 'CARD_MOTION_PASS'),
    'combat-card': ('combat-card', 'COMBAT_CARD_PLAY_PASS'),
    'card-targeting': ('card-targeting', r'CARD_TARGETING_TEST: \d+ checks; failures=\[\]'),
    'status': ('status', 'UNIT_STATUS_PASS'),
    'round-damage': ('round-damage', 'ROUND_DAMAGE_EFFECT_PASS'),
    'campfire': ('campfire', r'CAMPFIRE_TEST: \d+ checks, 0 failures'),
    'shop': ('shop', 'SHOP_TEST_PASS'),
    'game_session_smoke': ('game-session', 'GAME_SESSION_SMOKE_PASS'),
    'unit-lifecycle': ('unit-lifecycle', r'UNIT_LIFECYCLE_TEST: \d+ checks; failures=\[\]'),
}
STANDALONE = {
    'encyclopedia': ('encyclopedia_test.gd', r'ENCYCLOPEDIA_TEST: \d+ checks; failures=\[\]'),
    'route-events': ('route_events_test.gd', r'ROUTE_EVENTS_TEST: \d+ checks, 0 failures'),
    'random-map': ('procedural_map_test.gd', r'PROCEDURAL_MAP_TEST: \d+ checks; failures=\[\]'),
    'eslabong-preview-speed': ('eslabong_preview_speed_test.gd', r'ESLABONG_PREVIEW_SPEED_TEST: \d+ checks; failures=\[\]'),
    'eslabong-impact-alignment': ('eslabong_impact_alignment_test.gd', r'ESLABONG_IMPACT_ALIGNMENT_TEST: \d+ checks; failures=\[\]'),
    'eslabong-scale': ('eslabong_scale_test.gd', r'ESLABONG_SCALE_TEST: \d+ profiles; failures=\[\]'),
    'eslabong-skills': ('eslabong_skills_test.gd', r'ESLABONG_SKILLS_TEST: \d+ skills; failures=\[\]'),
    'eslabong-vfx': ('eslabong_vfx_test.gd', r'ESLABONG_VFX_TEST: \d+ items; failures=\[\]'),
    'config-cache': ('game_config_cache_test.gd', r'GAME_CONFIG_CACHE_TEST: \d+ checks; failures=\[\]'),
    'event-editor-layout': ('event_editor_layout_test.gd', r'EVENT_EDITOR_LAYOUT_TEST: \d+ checks; PASS'),
    'three-act': ('three_act_test.gd', r'THREE_ACT_TEST: \d+ checks; failures=\[\]'),
    'map-direct-apply': ('map_direct_apply_test.gd', r'MAP_DIRECT_APPLY_TEST: \d+ checks; failures=\[\]'),
    'settings-pause': ('settings_pause_test.gd', 'SETTINGS_PAUSE_PASS'),
    'settings-controls': ('settings_controls_test.gd', 'SETTINGS_CONTROLS_PASS'),
    'settings-audio': ('settings_audio_output_test.gd', 'SETTINGS_AUDIO_PASS'),
    'audio-library': ('audio_library_test.gd', r'AUDIO_LIBRARY_TEST: \d+ checks; PASS'),
    'package-tool': ('package_tool_test.gd', r'PACKAGE_TOOL_TEST: failures=\[\]'),
    'level-ui-preview': ('level_ui_preview_test.gd', r'LEVEL_UI_PREVIEW_TEST: \d+ checks; failures=\[\]'),
    'resources': ('resource_load_check.gd', r'RESOURCE_LOAD_CHECK: \d+ resources; failures=\[\]'),
    'fixed-map': ('fixed_map_import_test.gd', 'FIXED_MAP_IMPORT_PASS'),
    'map-editor': ('map_editor_test.gd', r'MAP_EDITOR_TEST: \d+ checks; PASS'),
    'events': ('event_system_test.gd', r'EVENT_SYSTEM_TEST: \d+ checks, 0 failures'),
    'treasure': ('treasure_node_test.gd', r'TREASURE_NODE_TEST: \d+ checks; PASS'),
    'game-config-editor': ('game_config_editor_test.gd', r'GAME_CONFIG_EDITOR_TEST: \d+ checks; failures=\[\]'),
    'wave-editor': ('wave_editor_test.gd', r'WAVE_EDITOR_TEST: \d+ checks; PASS'),
    'wave-preview': ('wave_preview_test.gd', r'WAVE_PREVIEW_TEST: \d+ checks; PASS'),
    'wave-loop': ('wave_loop_test.gd', r'WAVE_LOOP_TEST: \d+ checks; PASS'),
    'wave-spawn': ('wave_spawn_effect_test.gd', r'WAVE_SPAWN_EFFECT_TEST: \d+ checks; PASS'),
    'wave-spawn-floors': ('wave_spawn_floors_test.gd', r'WAVE_SPAWN_FLOORS_TEST: \d+ checks; failures=\[\]'),
    'level108-navigation': ('level108_navigation_test.gd', r'LEVEL108_NAVIGATION_TEST: \d+ checks; failures=\[\]'),
    'level108-cross-floor': ('level108_cross_floor_test.gd', r'LEVEL108_CROSS_FLOOR_TEST: \d+ checks; failures=\[\]'),
    'comic-ui': ('comic_ui_test.gd', 'COMIC_UI_TEST_PASS'),
    'mecha-assets': ('mecha_asset_check.gd', 'MECHA_GIRL_QA PASS'),
}
SCENES = {
    'rain': ('rain_weather_test.tscn', r'RAIN_WEATHER_TEST: failures=\[\]'),
    'rain-floors': ('rain_floors_test.tscn', r'RAIN_FLOORS_TEST: \d+ checks; failures=\[\]'),
    'snow': ('snow_weather_test.tscn', r'SNOW_WEATHER_TEST: failures=\[\]'),
    'snow-floors': ('snow_floors_test.tscn', r'SNOW_FLOORS_TEST: \d+ checks; failures=\[\]'),
    'river': ('dynamic_river_test.tscn', r'DYNAMIC_RIVER_PASS: failures=\[\]'),
    'river-tiles': ('river_tilemap_test.tscn', r'RIVER_TILEMAP_PASS: failures=\[\]'),
}
# Keep asset-specific QA available explicitly without failing every game regression
# when its independent example asset is not installed in this checkout.
OPTIONAL_ASSETS = {'mecha-assets': 'assets/MechaGirl/MechaGirl.tscn'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT_EXE', 'D:/Godot4/Godot_v4.6.2-stable_win64_console.exe'))
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--label', default='current')
    parser.add_argument('--out', type=Path, help='Log directory; defaults to .maintenance/checks/<label>.')
    parser.add_argument('--checks', nargs='+', help='Run only these named checks.')
    parser.add_argument('--timeout', type=float, default=60, help='Wall-clock limit per check, in seconds.')
    parser.add_argument('--max-log-mb', type=float, default=16, help='Combined output limit per check, in MiB.')
    parser.add_argument('--graphical', action='store_true', help='Run selected checks with the graphical renderer.')
    parser.add_argument('--list', action='store_true')
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error('Timeout must be a finite positive number.')
    if not math.isfinite(args.max_log_mb) or args.max_log_mb < 1 / 1024:
        parser.error('Log limit must be finite and at least 1 KiB.')
    checks = {name: (RUNNER, marker, ['--' + flag + '-regression'] if flag else [], False)
              for name, (flag, marker) in REGRESSIONS.items()}
    checks.update({name: ('tests/' + script, marker, [], False)
                   for name, (script, marker) in STANDALONE.items()})
    checks['random-map-sweep'] = ('tests/procedural_map_test.gd', r'PROCEDURAL_MAP_TEST: \d+ checks; failures=\[\]', ['--map-sweep'], False)
    checks.update({name: ('tests/' + scene, marker, [], True)
                   for name, (scene, marker) in SCENES.items()})
    if args.list:
        print('\n'.join(checks))
        return 0
    selected = args.checks or [name for name in checks
                              if name not in OPTIONAL_ASSETS
                              or (args.project / OPTIONAL_ASSETS[name]).is_file()]
    unknown = set(selected) - checks.keys()
    if unknown:
        parser.error('Unknown checks: ' + ', '.join(sorted(unknown)))
    root = args.project.resolve()
    if not (root / 'project.godot').is_file():
        parser.error('Project must contain project.godot.')
    if not re.fullmatch(r'[\w-]+', args.label):
        parser.error('Label must contain only letters, digits, underscores or hyphens.')
    out = (args.out or root / '.maintenance' / 'checks' / args.label).resolve()
    out.mkdir(parents=True, exist_ok=True)
    run_id = uuid.uuid4().hex[:12]
    userdata = out / 'userdata' / run_id
    userdata.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, APPDATA=str(userdata), LOCALAPPDATA=str(userdata),
               TEMP=str(userdata), TMP=str(userdata), PYTHONDONTWRITEBYTECODE='1')
    results = []
    for name in selected:
        script, marker, flags, scene = checks[name]
        engine_log = out / ('.%s-%s.engine.log' % (name, run_id))
        cmd = [args.godot, '--path', str(root), '--fixed-fps', '60', '--log-file', str(engine_log)]
        if not args.graphical:
            cmd.append('--headless')
        cmd += ['res://' + script] if scene else ['--script', 'res://' + script]
        cmd += ['--', '--no-mcp-server', '--test-timeout=%g' % args.timeout, *flags]
        log_path = out / ('.%s-%s.log' % (name, run_id))
        proc = run_guarded(cmd, cwd=root, env=env, log_path=log_path, engine_log=engine_log,
                           timeout=args.timeout, max_log_bytes=int(args.max_log_mb * 1024 * 1024))
        # The engine file is UTF-8 even when the Windows console uses a legacy codepage.
        log = (engine_log if engine_log.stat().st_size else log_path).read_text(encoding='utf-8', errors='replace')
        errors = list(dict.fromkeys(line for line in log.splitlines() if is_engine_error(line)))[:32]
        if not errors:
            errors.extend(proc.errors)
        if proc.stopped and (proc.stopped != 'engine error' or not errors):
            errors.append(proc.stopped)
        warnings = list(dict.fromkeys(line for line in log.splitlines() if 'WARNING:' in line))[:32]
        skipped = list(dict.fromkeys(line for line in log.splitlines()
                                    if 'skipped (headless)' in line or 'requires a graphical renderer' in line))
        if not re.search(marker, log):
            errors.append('Missing completion marker: ' + marker)
        passed = proc.exit_code == 0 and not errors
        result = dict(name=name, passed=passed, status=('partial' if skipped else 'passed') if passed else 'failed',
                      exit_code=proc.exit_code, stopped=proc.stopped, errors=errors,
                      warnings=warnings, skipped=skipped, seconds=proc.seconds, session_id=run_id)
        # Active processes never share file handles, even when callers reuse a label.
        # Publish bounded snapshots only after the child has stopped and logs were read.
        engine_log.replace(out / (name + '.engine.log'))
        log_path.replace(out / (name + '.log'))
        results.append(result)
        snapshot = out / ('.results-%s.tmp' % run_id)
        snapshot.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
        snapshot.replace(out / 'results.json')
        shown = dict(result)
        if len(shown['errors']) > 8:
            shown['error_count'] = len(shown['errors'])
            shown['errors'] = shown['errors'][:8] + ['Full errors are in the log and results.json.']
        print(json.dumps(shown, ensure_ascii=False), flush=True)
    return 0 if all(result['passed'] for result in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
