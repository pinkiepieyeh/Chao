// One-off migration for 0.14.0 (issues #50 #155). Idempotent.
//  - a card may declare its own category large / normal / small; deck limits read it before the faction's (#50)
//  - an effect's unit_filter may set not_chosen: true to leave out the unit the card or ability chose ("其余友方单位")
//  - value sources destroyed_attack_total / destroyed_health_total: the current attack and health of the units the same
//    group destroyed so far
// node tools/schema/add_0140_mechanics.mjs
import {readFileSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const DOCS = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'docs', 'cards');
const NEW_STATS = ['destroyed_attack_total', 'destroyed_health_total'];

function eachObject(value, visit) {
  if (Array.isArray(value)) value.forEach(item => eachObject(item, visit));
  else if (value && typeof value === 'object') { visit(value); for (const key of Object.keys(value)) eachObject(value[key], visit); }
}

function migrate(schema) {
  const counts = {filters: 0, stats: 0};
  eachObject(schema, node => {
    const filter = node?.properties?.op && node.properties.unit_filter;
    if (filter?.properties && !filter.properties.not_chosen) { filter.properties.not_chosen = {const: true}; counts.filters++; }
    if (Array.isArray(node?.enum) && node.enum.includes('friendly_turn_number')) for (const stat of NEW_STATS) if (!node.enum.includes(stat)) { node.enum.push(stat); counts.stats++; }
  });
  if (schema.properties?.faction_id && schema.properties.kind && !schema.properties.category) { schema.properties.category = {enum: ['large', 'normal', 'small']}; counts.category = 1; }
  return counts;
}

for (const file of ['card.schema.json', 'keyword.schema.json']) {
  const path = join(DOCS, file), raw = readFileSync(path, 'utf8');
  const schema = JSON.parse(raw);
  const counts = migrate(schema);
  const indent = raw.startsWith('{\n  ') || raw.startsWith('{\r\n  ') ? 2 : undefined;
  writeFileSync(path, JSON.stringify(schema, null, indent) + (raw.endsWith('\n') ? '\n' : ''));
  console.log(file, JSON.stringify(counts));
}
