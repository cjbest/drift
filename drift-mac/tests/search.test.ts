import { test } from "node:test";
import assert from "node:assert/strict";
import { searchNotes, type Note } from "../src/notebook/search.ts";

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
