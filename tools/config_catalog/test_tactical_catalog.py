"""Validate new tactical fields against an engine snapshot without writing game balance."""
import copy
import unittest
import catalog


class TacticalCatalogTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base = catalog.snapshot()
        cls.rows = {row['id']: row for row in cls.base['records']}

    def proposed(self, card, field, value, effect=True):
        document = copy.deepcopy(self.base)
        prefix = f'res://data/cards/{card}.tres'
        row = next(row for row in document['records']
                   if (row['id'].startswith(prefix + '::') if effect else row['id'] == prefix))
        next(item for item in row['fields'] if item['name'] == field)['value'] = value
        return document

    def test_all_tactical_amounts_can_be_edited(self):
        values = {'weakness': 3, 'vulnerability': 20.5, 'intimidation': 3,
                  'paralysis': 1.2, 'convert_enemy': 1, 'frenzy': 20.5,
                  'retreat_draw': 2, 'diverse_army': 3, 'keep_distance': 131.5,
                  'judger': 3}
        for card, value in values.items():
            with self.subTest(card=card):
                document = self.proposed(card, 'amount', value)
                catalog.plan(document, self.base, catalog.ROOT)

    def test_round_debuff_duration_cannot_be_extended(self):
        for card in ['weakness', 'vulnerability', 'intimidation', 'paralysis']:
            with self.subTest(card=card), self.assertRaises(ValueError):
                catalog.plan(self.proposed(card, 'lasting_rounds', 2), self.base, catalog.ROOT)

    def test_paralysis_window_cannot_overlap(self):
        with self.assertRaises(ValueError):
            catalog.plan(self.proposed('paralysis', 'interval', 0.5), self.base, catalog.ROOT)

    def test_frenzy_parameters_validate_and_remain_configurable(self):
        for field, value in [('crowded_unit_count', 4), ('crowded_stat_percent', 65),
                             ('solo_attack_bonus_percent', 60), ('solo_defence_bonus_percent', 40),
                             ('cooldown_reduction_percent', 25)]:
            with self.subTest(field=field):
                changes, files = catalog.plan(self.proposed('frenzy', field, value), self.base, catalog.ROOT)
                self.assertEqual(len(changes), 1)
                self.assertTrue(files)
        with self.assertRaises(ValueError):
            catalog.plan(self.proposed('frenzy', 'cooldown_reduction_percent', 100), self.base, catalog.ROOT)

    def test_distance_parameters_validate(self):
        changes, _ = catalog.plan(self.proposed('keep_distance', 'distance_for_max_bonus', 800), self.base, catalog.ROOT)
        self.assertEqual(len(changes), 1)
        with self.assertRaises(ValueError):
            catalog.plan(self.proposed('keep_distance', 'minimum_attack_percent', 140), self.base, catalog.ROOT)

    def test_enhancement_fields_are_exported_and_editable(self):
        for card, field, value, effect in [
            ('copy_ally', 'upgrade_cost_change', -2, False),
            ('mud_zone', 'upgrade_lasting_rounds', 2, True),
            ('convert_enemy', 'can_convert_elite', True, True),
            ('convert_enemy', 'upgrade_can_convert_elite', False, True),
            ('undying_army', 'amount', 1, True),
        ]:
            with self.subTest(field=field):
                changes, files = catalog.plan(self.proposed(card, field, value, effect), self.base, catalog.ROOT)
                self.assertEqual(len(changes), 1)
                self.assertTrue(files)

    def test_death_cost_penalty_requires_nonnegative_integer(self):
        for value in [-1, 1.5]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                catalog.plan(self.proposed('undying_army', 'amount', value), self.base, catalog.ROOT)

    def test_monster_rank_exports_and_can_be_edited(self):
        document = copy.deepcopy(self.base)
        row = next(row for row in document['records'] if row['id'] == 'res://data/units/elite_orc.tres')
        field = next(item for item in row['fields'] if item['name'] == 'monster_rank')
        self.assertEqual(field['value'], 1)
        field['value'] = 3
        changes, files = catalog.plan(document, self.base, catalog.ROOT)
        self.assertEqual(len(changes), 1)
        self.assertIn('monster_rank = 3', files['data/units/elite_orc.tres'])


if __name__ == '__main__':
    unittest.main()
