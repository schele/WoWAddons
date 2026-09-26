import { test } from 'node:test';
import assert from 'node:assert/strict';
import { itemIdsOf } from '../lib/items.mjs';

test('every item the instances list, once each, in id order', () => {
  const instances = [
    {
      bosses: [{ loot: [{ id: 300 }, { id: 100 }] }, { loot: [{ id: 100 }] }],
      notable: { trash: [{ id: 200 }], objects: [{ id: 400 }] },
    },
    { bosses: [{ loot: [{ id: 100 }, { id: 50 }] }], notable: { trash: [], objects: [] } },
  ];
  assert.deepEqual(itemIdsOf(instances), [50, 100, 200, 300, 400]);
});
