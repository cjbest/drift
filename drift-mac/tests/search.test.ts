import { test } from "node:test";
import assert from "node:assert/strict";
import { searchNotes, type Note } from "../src/notebook/search.ts";
import { filenameTitle, isPinnedPath } from "../src/notebook/filename.ts";

const note = (title: string, modified: number, text = title): Note => ({
  path: title + ".md", title, modified, text, size: text.length,
});
const paths = (
  notes: Note[],
  access: Record<string, number> = {},
  query = "",
  current: string | null = null,
) => searchNotes(notes, query, access, current).map(hit => hit.note.path);

test("last-used dates follow the latest open or edit, with stable ties and an edit fallback", () => {
  const notes = [
    note("Opened", 1),
    note("Edited", 6),
    note("Z tie", 3),
    note("Never opened", 2),
    note("A tie", 1),
  ];
  const access = { "Opened.md": 5, "Edited.md": 2, "A tie.md": 3 };
  assert.deepEqual(
    searchNotes(notes, "", access, null).map(hit => [hit.note.path, hit.lastUsed]),
    [["Edited.md", 6], ["Opened.md", 5], ["A tie.md", 3], ["Z tie.md", 3], ["Never opened.md", 2]],
  );
  assert.deepEqual(paths(notes, access, "", "Opened.md"), [
    "Edited.md", "A tie.md", "Z tie.md", "Never opened.md",
  ]);
});

test("search keeps title relevance ahead of last use and can find the current note", () => {
  const notes = [
    note("Other", 5, "A notebook with a needle in the body"),
    note("Older needle", 2),
    note("Needle", 1),
    note("Newer needle", 3),
  ];
  assert.deepEqual(paths(notes, { "Older needle.md": 4 }, "needle", "Needle.md"), [
    "Needle.md", "Older needle.md", "Newer needle.md", "Other.md",
  ]);
});

test("synced filename pins come first without changing recency within each group", () => {
  const notes = [
    note("Recent", 20),
    { ...note("Pinned old", 1), path: "Pinned old.pinned.md" },
    { ...note("Pinned opened", 2), path: "Pinned opened.PINNED.MD" },
    note("Older", 3),
  ];
  const access = { "Pinned opened.PINNED.MD": 10 };
  assert.deepEqual(paths(notes, access), [
    "Pinned opened.PINNED.MD", "Pinned old.pinned.md", "Recent.md", "Older.md",
  ]);
  assert.deepEqual(paths(notes, access, "", "Pinned opened.PINNED.MD"), [
    "Pinned old.pinned.md", "Recent.md", "Older.md",
  ]);
});

test("pins do not outrank title relevance or more recent matches during search", () => {
  const notes = [
    { ...note("Other", 100, "needle"), path: "Other.pinned.md" },
    { ...note("Older needle", 1), path: "Older needle.pinned.md" },
    note("Newer needle", 10),
    note("Needle", 2),
  ];
  assert.deepEqual(paths(notes, {}, "needle"), [
    "Needle.md", "Newer needle.md", "Older needle.pinned.md", "Other.pinned.md",
  ]);
});

test("pin metadata stays out of display titles while ordinary names stay intact", () => {
  for (const path of ["A.pinned.md", "A.PINNED.MD"]) {
    assert.equal(isPinnedPath(path), true);
    assert.equal(filenameTitle(path), "A");
  }
  assert.equal(isPinnedPath("A.pinned 1.md"), false);
  assert.equal(filenameTitle("A.pinned 1.md"), "A.pinned 1");
  assert.equal(filenameTitle("A.md"), "A");
});
