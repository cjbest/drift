import { test } from "node:test";
import assert from "node:assert/strict";
import { fresh, SaveQueue, dirty } from "../src/notebook/session.ts";
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => (resolve = r));
  return { promise, resolve };
}
test("a queued edit that returns to the old baseline still saves after the in-flight write", async () => {
  const s = { ...fresh(), path: "A.md", baseline: "A", text: "B" };
  const gate = deferred<any>(),
    calls: any[] = [];
  const q = new SaveQueue(
    async (d) => {
      calls.push(d);
      return calls.length === 1
        ? gate.promise
        : { path: "A.md", text: d.text, conflict: false };
    },
    () => {},
    () => {},
  );
  const pending = q.flush(s);
  s.text = "A";
  gate.resolve({ path: "A.md", text: "B", conflict: false });
  await pending;
  assert.deepEqual(
    calls.map((d) => d.text),
    ["B", "A"],
  );
  assert.equal(dirty(s), false);
});
test("parallel flush callers share a writer and failed writes retain baseline", async () => {
  const s = { ...fresh(), path: "A.md", baseline: "A", text: "B" };
  let calls = 0;
  const q = new SaveQueue(
    async () => {
      calls++;
      throw Error("offline");
    },
    () => {},
    () => {},
  );
  await Promise.allSettled([q.flush(s), q.flush(s)]);
  assert.equal(calls, 1);
  assert.equal(s.baseline, "A");
  assert.equal(dirty(s), true);
});
test("renaming while typing uses the acknowledged path for the next write", async () => {
  const s = { ...fresh(), path: "Old.md", baseline: "Old", text: "New" };
  const gate = deferred<any>(),
    calls: any[] = [];
  const q = new SaveQueue(
    async (d) => {
      calls.push(d);
      return calls.length === 1
        ? gate.promise
        : { path: "New.md", text: d.text, conflict: false };
    },
    () => {},
    () => {},
  );
  const pending = q.flush(s);
  s.text = "New\nmore";
  gate.resolve({ path: "New.md", text: "New", conflict: false });
  await pending;
  assert.equal(calls[1].path, "New.md");
  assert.equal(calls[1].baseline, "New");
  assert.equal(s.text, "New\nmore");
});
