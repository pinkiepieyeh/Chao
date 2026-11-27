// One-off migration for 0.15.0 (issues #156 #157 #158 #167 #168 #169 #170 #171 #172 #173). Idempotent.
//  - select_units random: true picks `max` units at random instead of asking (#156)
//  - an effect's unit_filter may set attack_rank lowest / highest among the units the effect would reach (#171)
//  - remove_hand without card_name removes the player's whole hand (#169)
//  - destroy salvage: true gives the effect's owner a salvage copy of each unit it destroys (#170 #171)
//  - new op salvage_copy {player}: a salvage copy of the ability's own card, e.g. in a granted on_death (#170)
//  - transfer_card from: opponent takes from the opponent's zones into the owner's; reveal: N shows N cards at random to
//    choose from; hand_cost_delta changes the cost of the card that enters the hand (#168)
//  - grant_keyword / remove_keyword know core.unpinnable and core.poisonous; modify_cards may grant a keyword to the
//    cards it changes through an on_play grant_keyword (#157 #172)
// node tools/schema/add_0150_mechanics.mjs
import {readFileSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const DOCS = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'docs', 'cards');
const clone = value => structuredClone(value);
const NEW_KEYWORDS = ['core.unpinnable', 'core.poisonous'];

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
  const counts = {select: 0, rank: 0, remove_hand: 0, destroy: 0, transfer: 0, keywords: 0, modify_cards: 0, ops: 0};
  let grantKeyword = null;
  eachObject(schema, node => { if (!grantKeyword && opOf(node) === 'grant_keyword' && node.properties.target?.enum?.includes('self')) grantKeyword = node; });
  eachObject(schema, node => {
    const op = opOf(node), props = node?.properties;
    if (op === 'select_units' && !props.random) { props.random = {const: true}; counts.select++; }
    if (op && props.unit_filter?.properties && !props.unit_filter.properties.attack_rank) { props.unit_filter.properties.attack_rank = {enum: ['lowest', 'highest']}; counts.rank++; }
    if (op === 'remove_hand' && node.required.includes('card_name')) { node.required = node.required.filter(key => key !== 'card_name'); counts.remove_hand++; }
    if (op === 'destroy' && !props.salvage) { props.salvage = {const: true}; counts.destroy++; }
    if (op === 'transfer_card' && !props.from) {
      props.from = {const: 'opponent'};
      props.reveal = {type: 'integer', minimum: 2, maximum: 5};
      props.hand_cost_delta = {type: 'integer', minimum: -5, maximum: 5};
      counts.transfer++;
    }
    if ((op === 'grant_keyword' || op === 'remove_keyword') && Array.isArray(props.keyword_id?.enum)) for (const id of NEW_KEYWORDS) if (!props.keyword_id.enum.includes(id)) { props.keyword_id.enum.push(id); counts.keywords++; }
    if (op === 'modify_cards' && grantKeyword) {
      const effects = props.grant_abilities?.items?.properties?.effects?.items?.oneOf;
      if (Array.isArray(effects) && !hasOp(effects, 'grant_keyword')) {
        const granted = clone(grantKeyword);
        granted.properties.target = {const: 'self'};
        granted.properties.duration = {enum: ['battle', 'match']};
        for (const key of Object.keys(granted.properties)) if (!['op', 'target', 'keyword_id', 'keyword_version', 'duration'].includes(key)) delete granted.properties[key];
        granted.required = ['op', 'target', 'keyword_id', 'keyword_version', 'duration'];
        effects.push(granted);
        counts.modify_cards++;
      }
    }
  });
  // modify_cards' grant list was cloned before the keyword enums grew; give it the new ids too.
  eachObject(schema, node => {
    if (opOf(node) === 'grant_keyword' && Array.isArray(node.properties.keyword_id?.enum)) for (const id of NEW_KEYWORDS) if (!node.properties.keyword_id.enum.includes(id)) { node.properties.keyword_id.enum.push(id); counts.keywords++; }
  });
  // Granted abilities (grant_ability, modify_cards) have their own shorter effect list; salvage_copy belongs there too (#170).
  eachArray(schema, list => {
    if (!hasOp(list, 'tax_opponent_plays') || !hasOp(list, 'forbid_deploy') || hasOp(list, 'fight') || hasOp(list, 'salvage_copy')) return;
    list.push({type: 'object', additionalProperties: false, properties: {op: {const: 'salvage_copy'}, player: {enum: ['owner', 'opponent']}}, required: ['op', 'player']});
    counts.ops++;
  });
  // Built-in keyword implementations the engine now knows (#157 #167 #172).
  eachObject(schema, node => {
    const ids = node?.properties?.builtin_id?.enum;
    if (Array.isArray(ids) && ids.includes('core.revive.v1')) for (const id of ['core.salvage.v2', 'core.unpinnable.v1', 'core.poisonous.v1']) if (!ids.includes(id)) { ids.push(id); counts.keywords++; }
  });
  eachArray(schema, list => {
    if (!hasOp(list, 'retreat') || !hasOp(list, 'fight') || hasOp(list, 'salvage_copy')) return;
    list.push({type: 'object', additionalProperties: false, properties: {op: {const: 'salvage_copy'}, player: {enum: ['owner', 'opponent']}}, required: ['op', 'player']});
    counts.ops++;
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
