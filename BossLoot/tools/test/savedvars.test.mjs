import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseSavedVariables } from '../lib/savedvars.mjs';

test('reads what the game writes: nested tables, keys of each kind, comments', () => {
  const text = [
    '',
    'BossLootDB = {',
    '\t["recorded"] = {',
    '\t\t["recorder"] = "a1b2c3d4",',
    '\t\t["sources"] = {',
    '\t\t\t["npc:6910"] = {',
    '\t\t\t\t["kills"] = 5,',
    '\t\t\t\t["name"] = "Revelosh",',
    '\t\t\t\t["items"] = {',
    '\t\t\t\t\t[9387] = 2,',
    '\t\t\t\t},',
    '\t\t\t},',
    '\t\t},',
    '\t\t["seen"] = {',
    '\t\t\t"Creature-0-1-70-47-6910-A", -- [1]',
    '\t\t},',
    '\t\t["ratio"] = -0.25,',
    '\t\t["on"] = true,',
    '\t\t["off"] = false,',
    '\t\t["none"] = nil,',
    '\t},',
    '}',
    'Other = 3',
  ].join('\n');
  const vars = parseSavedVariables(text);
  const recorded = vars.BossLootDB.recorded;
  assert.equal(recorded.recorder, 'a1b2c3d4');
  assert.equal(recorded.sources['npc:6910'].kills, 5);
  assert.equal(recorded.sources['npc:6910'].items['9387'], 2);
  assert.equal(recorded.seen['1'], 'Creature-0-1-70-47-6910-A');
  assert.equal(recorded.ratio, -0.25);
  assert.equal(recorded.on, true);
  assert.equal(recorded.off, false);
  assert.equal(recorded.none, null);
  assert.equal(vars.Other, 3);
});

test('reads escapes in strings', () => {
  const vars = parseSavedVariables('X = "Doom\'rel \\"the\\" \\\\ a\\nb\\065"');
  assert.equal(vars.X, 'Doom\'rel "the" \\ a\nbA');
});

test('refuses what it cannot read', () => {
  assert.throws(() => parseSavedVariables('X = {'), /saved variables/);
});
