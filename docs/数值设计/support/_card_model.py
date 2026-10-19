import sys, json, math
sys.path.insert(0, 'docs/数值设计/support')
import _extract as ex

K = {
 'ATTACK_UP':20, 'DEFENCE_UP':25, 'HEAL_PERCENT':1.2, 'POISON_ON_HIT':8,
 'DEATH_EXPLOSION':1.4, 'COPY_ALLY':90, 'DAMAGE_ZONE':12*1.3,
 'MUD_ZONE':55, 'DRAW':35, 'LOCK_DRAW':-25, 'PAY_HP':-2,
 'ENERGY_EACH_ROUND':45, 'DEATH_ATTACK_AURA':45, 'RANDOM_PLAY':45,
 'RECALL_ALLY':45, 'GAIN_ENERGY':90, 'MAX_HP_UP':3, 'RETAIN_ALLIES':130,
 'WEAKNESS':22, 'VULNERABILITY':2.5, 'DEFENCE_DOWN':22, 'PARALYSIS':40,
 'CONVERT_ENEMY':110, 'FRENZY':80, 'RETREAT_DRAW':55, 'DIVERSE_ARMY':60,
 'KEEP_DISTANCE':45, 'JUDGER':70, 'COMRADE':90, 'TEMPORARY_UPGRADE':75,
 'BLEED':0.8, 'HEALING_BAN':45, 'ARMOR_SHRED':55, 'SLEEP':45,
 'SHIELD':0.9, 'OVERFLOW_SHIELD':55, 'MISSING_HEALTH_SHIELD':0.7,
 'KNOCKBACK_IMMUNITY':40, 'TUTOR_UNIT':65, 'DISCARD_DRAW':35,
 'SACRIFICE':70, 'RESURRECT':100, 'DEATH_DRAW':60, 'ARMY_ATTACK':45,
 'ARMY_DEFENCE':45, 'ARMY_SPEED':1.2, 'BATTLE_STANDARD':65,
 'SPIKE_TRAP':1.2, 'TRANSCRIBE':80, 'REFORMATION':65, 'HAND_DISCOUNT':30,
 'OVERDRAFT':65, 'THRIFT':90,
}
NAMES = ['ATTACK_UP','HEAL_PERCENT','DEFENCE_UP','POISON_ON_HIT','DEATH_EXPLOSION','?','COPY_ALLY','DAMAGE_ZONE','MUD_ZONE','DRAW','LOCK_DRAW','PAY_HP','ENERGY_EACH_ROUND','DEATH_ATTACK_AURA','RANDOM_PLAY','RECALL_ALLY','CUSTOM','GAIN_ENERGY','MAX_HP_UP','RETAIN_ALLIES','WEAKNESS','VULNERABILITY','DEFENCE_DOWN','PARALYSIS','CONVERT_ENEMY','FRENZY','RETREAT_DRAW','DIVERSE_ARMY','KEEP_DISTANCE','JUDGER','COMRADE','TEMPORARY_UPGRADE','BLEED','HEALING_BAN','ARMOR_SHRED','SLEEP','SHIELD','OVERFLOW_SHIELD','MISSING_HEALTH_SHIELD','KNOCKBACK_IMMUNITY','TUTOR_UNIT','DISCARD_DRAW','SACRIFICE','RESURRECT','DEATH_DRAW','ARMY_ATTACK','ARMY_DEFENCE','ARMY_SPEED','BATTLE_STANDARD','SPIKE_TRAP','TRANSCRIBE','REFORMATION','HAND_DISCOUNT','OVERDRAFT','THRIFT']

def ev(e):
    k = NAMES[e.get('kind', 0)]
    a = e.get('amount', 0)
    up = e.get('upgrade_amount', 0)
    def value(kind, amount):
        if kind == 'ATTACK_UP': return amount*K[kind]
        if kind == 'DEFENCE_UP': return amount*K[kind]
        if kind == 'HEAL_PERCENT': return amount*K[kind]
        if kind == 'POISON_ON_HIT': return amount*K[kind]
        if kind == 'DEATH_EXPLOSION': return amount*K[kind]
        if kind == 'COPY_ALLY': return K[kind]
        if kind == 'DAMAGE_ZONE': return amount*K[kind]
        if kind == 'MUD_ZONE': return K[kind] + 15*max(0, e.get('lasting_rounds',2)-2)
        if kind == 'DRAW': return amount*K[kind]
        if kind == 'LOCK_DRAW': return K[kind]
        if kind == 'PAY_HP': return amount*K[kind]
        if kind == 'ENERGY_EACH_ROUND': return amount*K[kind]
        if kind == 'DEATH_ATTACK_AURA': return amount*K[kind]
        if kind == 'RANDOM_PLAY': return amount*K[kind]
        if kind == 'RECALL_ALLY': return K[kind]
        if kind == 'GAIN_ENERGY': return amount*K[kind]
        if kind == 'MAX_HP_UP': return amount*K[kind]
        if kind == 'RETAIN_ALLIES': return K[kind] - 15*amount
        if kind == 'WEAKNESS': return amount*K[kind]
        if kind == 'VULNERABILITY': return amount*K[kind]
        if kind == 'DEFENCE_DOWN': return amount*K[kind]
        if kind == 'PARALYSIS': return amount*K[kind]
        if kind == 'CONVERT_ENEMY': return K[kind]
        if kind == 'FRENZY': return K[kind]
        if kind == 'RETREAT_DRAW': return K[kind] + 15*amount
        if kind == 'DIVERSE_ARMY': return K[kind] + 20*amount
        if kind == 'KEEP_DISTANCE': return K[kind] + 1.5*(amount-100)
        if kind == 'JUDGER': return K[kind] + 10*amount
        if kind == 'COMRADE': return K[kind]
        if kind == 'TEMPORARY_UPGRADE': return K[kind]
        if kind == 'BLEED': return amount*e.get('status_seconds',8)*K[kind]
        if kind == 'HEALING_BAN': return K[kind] + 2*e.get('status_seconds',8)
        if kind == 'ARMOR_SHRED': return K[kind]
        if kind == 'SLEEP': return K[kind] + 3*e.get('status_seconds',5)
        if kind == 'SHIELD': return amount*K[kind]
        if kind == 'OVERFLOW_SHIELD': return K[kind]
        if kind == 'MISSING_HEALTH_SHIELD': return amount*K[kind]
        if kind == 'KNOCKBACK_IMMUNITY': return K[kind]
        if kind == 'TUTOR_UNIT': return K[kind]
        if kind == 'DISCARD_DRAW': return amount*K[kind]
        if kind == 'SACRIFICE': return K[kind] + 40*amount
        if kind == 'RESURRECT': return K[kind]
        if kind == 'DEATH_DRAW': return K[kind]
        if kind == 'ARMY_ATTACK': return amount*K[kind]
        if kind == 'ARMY_DEFENCE': return amount*K[kind]
        if kind == 'ARMY_SPEED': return amount*K[kind]
        if kind == 'BATTLE_STANDARD': return K[kind]
        if kind == 'SPIKE_TRAP': return amount*K[kind] + 30
        if kind == 'TRANSCRIBE': return K[kind]
        if kind == 'REFORMATION': return K[kind]
        if kind == 'HAND_DISCOUNT': return amount*K[kind]
        if kind == 'OVERDRAFT': return amount*K[kind] - 15*e.get('next_round_penalty',3)
        if kind == 'THRIFT': return K[kind]
        return 0
    return value(k, a), value(k, a+up)

if __name__ == '__main__':
    cards = ex.cards()
    rows = []
    for c in cards:
        base = sum(ev(e)[0] for e in c['effects'])
        up = sum(ev(e)[1] for e in c['effects'])
        cost = c['cost']
        budget = [40, 80, 160, 240, 0, 400][cost] if cost <= 5 else 400
        rows.append((c['name'], cost, c['rarity'], round(base), round(up), round(up-base), budget))
    rows.sort(key=lambda r: (r[1], -r[3]))
    for r in rows:
        print(f'{r[0]:10} {r[1]}c r{r[2]} base={r[3]:4} up={r[4]:4} delta={r[5]:4} target>={r[6]}')
