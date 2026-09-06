import { test } from "node:test";
import assert from "node:assert/strict";
import { cascadeWindow } from "../src/notebook/window-placement.ts";
test("new windows cascade from their parent and wrap within a monitor's work area", () => {
  const area = { x: -1440, y: 25, width: 1440, height: 875 };
  const first = cascadeWindow(
    { x: -1300, y: 70, width: 900, height: 700 },
    area,
  );
  assert.deepEqual(first, { x: -1272, y: 98, width: 900, height: 700 });
  const edge = cascadeWindow(
    { x: -900, y: 200, width: 900, height: 700 },
    area,
  );
  assert.deepEqual(edge, { x: -1424, y: 41, width: 900, height: 700 });
  const oversized = cascadeWindow(
    { x: 0, y: 0, width: 2000, height: 1000 },
    area,
  );
  assert.deepEqual(oversized, { ...area });
});
