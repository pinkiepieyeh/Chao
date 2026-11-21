// One-off migration for 0.13.0 (issues #137 #151). Idempotent. #144 (kredit slots up to 24) and #152 (庇护, a template
// keyword over the "庇护" stack) need no schema change.
//  - counter_trigger may be an array of 2-8 distinct triggers; the counter springs on any of them (#137)
//  - select_units may pick up to 5 units (#151)
//  - modify_stats, grant_keyword and grant_unit_class may target "summoned" (#151)
//  - new branch op if_destroyed {tiers: [{min: 1-5, effects}, ...]}: after the group's destroy of selected_units, every
//    tier whose min is reached runs, in order (#151)
// node tools/schema/add_0130_mechanics.mjs
import {readFileSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const DOCS = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'docs', 'cards');
const clone = value => structuredClone(value);
const SUMMONED_OPS = ['modify_stats', 'grant_keyword', 'grant_unit_class'];

function eachArray(value, visit) {
  if (Array.isArray(value)) { visit(value); value.forEach(item => eachArray(item, visit)); }
  else if (value && typeof value === 'object') for (const key of Object.keys(value)) eachArray(value[key], visit);
}
function eachObject(value, visit) {
  if (Array.isArray(value)) value.forEach(item => eachObject(item, visit));
  else if (value && typeof value === 'object') { visit(value); for (const key of Object.keys(value)) eachObject(value[key], visit); }
}
const opOf = entry => entry?.properties?.op?.const;
const hasOp = (list, op) => list.some(entry => opOf(entry) === op);

function migrate(schema) {
  const counts = {counter: 0, select: 0, summoned: 0, ops: 0};
  eachObject(schema, node => {
    const props = node?.properties;
    const trigger = props?.counter_trigger;
    if (Array.isArray(trigger?.oneOf) && trigger.oneOf.some(entry => Array.isArray(entry.enum)) && !trigger.oneOf.some(entry => entry.type === 'array')) {
      const names = trigger.oneOf.find(entry => Array.isArray(entry.enum)).enum;
      trigger.oneOf.splice(1, 0, {type: 'array', items: {enum: clone(names)}, minItems: 2, maxItems: names.length, uniqueItems: true});
      counts.counter++;
    }
    if (trigger?.type === 'string') { props.counter_trigger = {oneOf: [{type: 'string'}, {type: 'array'}]}; counts.counter++; }
    const op = opOf(node);
    if (op === 'select_units') for (const key of ['min', 'max']) if (props[key]?.maximum === 3) { props[key].maximum = 5; counts.select++; }
    if (SUMMONED_OPS.includes(op) && Array.isArray(props.target?.enum) && !props.target.enum.includes('summoned')) { props.target.enum.push('summoned'); counts.summoned++; }
  });
  eachArray(schema, list => {
    const killed = list.find(entry => opOf(entry) === 'if_killed');
    if (!killed) return;
    const tiers = {type: 'array', minItems: 1, maxItems: 5, items: {type: 'object', additionalProperties: false, properties: {min: {type: 'integer', minimum: 1, maximum: 5}, effects: clone(killed.properties.effects)}, required: ['min', 'effects']}};
    const op = {type: 'object', additionalProperties: false, properties: {op: {const: 'if_destroyed'}, tiers}, required: ['op', 'tiers']};
    const index = list.findIndex(entry => opOf(entry) === 'if_destroyed');
    if (index < 0) { list.push(op); counts.ops++; }
    else if (!list[index].properties.tiers) { list[index] = op; counts.ops++; }
  });
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
