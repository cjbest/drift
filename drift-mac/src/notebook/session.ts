export interface Draft {
  id: string;
  path: string | null;
  baseline: string | null;
  text: string;
}
export interface Saved {
  path: string | null;
  text: string;
  conflict: boolean;
}
export interface Session extends Draft {
  revision: number;
}
export type Save = (draft: Draft) => Promise<Saved>;
export const fresh = (): Session => ({
  id: crypto.randomUUID(),
  path: null,
  baseline: null,
  text: "",
  revision: 0,
});
export const dirty = (s: Session) =>
  s.baseline === null ? !!s.text.trim() : s.text !== s.baseline;
export const snapshot = (s: Session): Draft => ({
  id: s.id,
  path: s.path,
  baseline: s.baseline,
  text: s.text,
});

/** One writer per document; a response acknowledges only the text it actually wrote. */
export class SaveQueue {
  private pending = new Map<string, Promise<void>>();
  private save: Save;
  private checkpoint: (s: Session) => void;
  private changed: (s: Session, conflict: boolean) => void;
  constructor(
    save: Save,
    checkpoint: (s: Session) => void,
    changed: (s: Session, conflict: boolean) => void,
  ) {
    this.save = save;
    this.checkpoint = checkpoint;
    this.changed = changed;
  }
  flush(session: Session): Promise<void> {
    const existing = this.pending.get(session.id);
    if (existing) return existing;
    const task = (async () => {
      while (dirty(session)) {
        const result = await this.save(snapshot(session));
        session.path = result.path;
        session.baseline = result.text;
        this.checkpoint(session);
        this.changed(session, result.conflict);
      }
    })();
    this.pending.set(session.id, task);
    void task.finally(() => this.pending.delete(session.id)).catch(() => {});
    return task;
  }
}
