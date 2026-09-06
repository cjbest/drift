export interface Note {
  path: string;
  title: string;
  modified: number;
  size: number;
  text?: string;
}
export interface Hit {
  note: Note;
  from: number;
  length: number;
  excerpt: string;
  before: string;
  match: string;
  after: string;
}
export function searchNotes(
  notes: Note[],
  query: string,
  access: Record<string, number>,
  current: string | null,
): Hit[] {
  const q = query.trim().toLocaleLowerCase();
  const hits = notes.flatMap((note) => {
    const text = note.text ?? "";
    const titleMatch = note.title.toLocaleLowerCase().indexOf(q);
    const from = q ? text.toLocaleLowerCase().indexOf(q) : -1;
    if (q && titleMatch < 0 && from < 0) return [];
    if (!q && note.path === current) return [];
    const body = text.indexOf("\n") + 1;
    const start = from >= 0 ? Math.max(0, from - 38) : body;
    const end = Math.min(
      text.length,
      (from >= 0 ? from + q.length : start) + 160,
    );
    const clean = (s: string) => s.replace(/\s+/g, " ");
    return [
      {
        note,
        from,
        length: q.length,
        excerpt: clean(text.slice(start, end)),
        before:
          from >= 0
            ? (start > 0 ? "…" : "") + clean(text.slice(start, from))
            : "",
        match: from >= 0 ? text.slice(from, from + q.length) : "",
        after:
          from >= 0
            ? clean(text.slice(from + q.length, end)) +
              (end < text.length ? "…" : "")
            : "",
      },
    ];
  });
  return hits.sort((a, b) => {
    if (q) {
      const score = (h: Hit) =>
        h.note.title.toLocaleLowerCase() === q
          ? 2
          : h.note.title.toLocaleLowerCase().includes(q)
            ? 1
            : 0;
      const delta = score(b) - score(a);
      if (delta) return delta;
    }
    return (
      Math.max(b.note.modified, access[b.note.path] ?? 0) -
        Math.max(a.note.modified, access[a.note.path] ?? 0) ||
      a.note.path.localeCompare(b.note.path)
    );
  });
}
