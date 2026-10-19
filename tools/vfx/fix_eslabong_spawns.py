"""Keep recovered secondary visuals at their requested world-space anchor.

Runs after the namespace/compatibility pass; also supports updating the checked
in library. Rewrites are idempotent and never touch the original installation.
"""
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
FUNCTION = re.compile(r'^func ([^\n]+)\n[\s\S]*?(?=^func |^static func |\Z)', re.M)
ADD = re.compile(r'^(\t+)([\w.()]+)\.add_child\((\w+)\)\s*$')


def detached_positions(body):
    lines = body.splitlines(keepends=True)
    calls = [(i, ADD.fullmatch(line.rstrip('\n'))) for i, line in enumerate(lines)]
    calls = [(i, m) for i, m in calls if m]
    for index, call in calls:
        indent, parent, child = call.groups()
        if sum(m[3] == child for _, m in calls) != 1:
            continue  # Multi-branch spawns need their branch-specific anchor.
        aliases = {child}
        for line in lines[:index]:
            alias = re.search(r'var (\w+)\s*(?::\s*(?:Node2D)?)?\s*=\s*' + re.escape(child) + r' as Node2D', line)
            if alias:
                aliases.add(alias[1])
        positions = []
        for n, line in enumerate(lines[:index]):
            match = re.fullmatch(r'\t+(\w+)\.global_position = (.+)\n?', line)
            if match and match[1] in aliases and not match[2].endswith('('):
                positions.append((n, match[2]))
        if len(positions) != 1:
            continue
        old_index, world = positions[0]
        lines[old_index] = ''
        rotations = []
        for n, line in enumerate(lines[:index]):
            match = re.fullmatch(r'\t+(\w+)\.global_rotation = (.+)\n?', line)
            if match and match[1] in aliases:
                rotations.append(f'{indent}{child}.global_rotation = {match[2]}\n')
                lines[n] = ''
        lines[index] = f'{indent}VFXPool.attach_for(self, {child}, {world}, {parent})\n' + ''.join(rotations)
    return ''.join(lines)


def rewrite_spawns(text, filename):
    def rewrite(match):
        signature = match[1]
        body = match[0]
        if '_sfx(' in signature or '_sfx()' in signature:
            return body
        body = detached_positions(body)
        if signature.startswith(('_spawn_ground_decal(', '_spawn_extra_decal(')):
            fallback = 'Vector2.ZERO'
            if filename in ['ElementalImpactVFX.gd', 'HammerOfHeavenImpactVFX.gd']:
                fallback = 'decal_offset'
            if filename == 'InfernusImpactVFX.gd':
                fallback = 'Vector2(0, 10)'
            if filename == 'IceBombImpactVFX.gd':
                fallback = 'Vector2(0, 8)'
            anchor = f'VFXPool.ground_position_for(self, {fallback})'
            if filename == 'HammerOfHeavenImpactVFX.gd':
                anchor = f'(ground_impact_position if ground_impact_position != Vector2.ZERO else {anchor})'
            body = body.replace('scene_root.add_child(decal)', f'VFXPool.attach_for(self, decal, {anchor}, scene_root)')
            body = re.sub(r'(\.(?:global_position) = )[^\n]+', lambda m: m[1] + anchor, body)
        if filename == 'HammerOfHeavenImpactVFX.gd' and signature.startswith('_spawn_extra_holy_puffs('):
            body = body.replace('scene_root.add_child(puff)', 'VFXPool.attach_for(self, puff, to_global(spawn_offsets[i]), scene_root)')
            body = body.replace('puff.global_position = global_position + spawn_offsets[i]', 'puff.global_position = to_global(spawn_offsets[i])')
        if filename == 'TheOneImpactVFX.gd' and signature.startswith('_spawn_blood_sparks('):
            body = body.replace('parent.add_child(sparks)', 'VFXPool.attach_for(self, sparks, global_position, parent)')
        if filename == 'RicochetBladeVFX.gd' and signature.startswith('_spawn_impact_vfx('):
            body = body.replace('scene_root.add_child(vfx)', 'VFXPool.attach_for(self, vfx, pos, scene_root)')
        if filename == 'ThinBeam.gd' and signature.startswith('_spawn_scene('):
            body = body.replace('parent.add_child(inst)', 'VFXPool.attach_for(self, inst, world_pos, parent)')
        if filename == 'Projectile.gd' and signature.startswith('_play_impact_fx('):
            body = body.replace('hit_target.add_child(vfx)', 'VFXPool.attach_for(self, vfx, spawn_pos, hit_target)')
            body = body.replace('tree.current_scene.add_child(vfx)', 'VFXPool.attach_for(self, vfx, spawn_pos, tree.current_scene)')
        return body
    return FUNCTION.sub(rewrite, text)


def main():
    changed = []
    for path in sorted((ROOT/'assets/effect/eslabong_vfx/source').rglob('*.gd')):
        before = path.read_text(encoding='utf-8')
        after = rewrite_spawns(before, path.name)
        if before != after:
            assert rewrite_spawns(after, path.name) == after, path
            changed.append(str(path.relative_to(ROOT)))
            if '--apply' in sys.argv:
                path.write_text(after, encoding='utf-8', newline='\n')
    print(json.dumps({'applied':'--apply' in sys.argv,'changed':changed},ensure_ascii=True))


if __name__ == '__main__':
    main()
