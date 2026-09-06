import {
  createSignal,
  createEffect,
  createMemo,
  onMount,
  on,
  For,
  Show,
} from "solid-js";
import { searchNotes } from "../notebook/search";
import type { Note, Hit } from "../notebook/search";
import "./QuickOpen.css";

interface Props {
  notes: Note[];
  access: Record<string, number>;
  current: string | null;
  loading: boolean;
  unavailable?: boolean;
  onSelect: (hit: Hit, newWindow: boolean) => void;
  onClose: () => void;
  onActive: (hit: Hit | undefined) => void;
}
function dateLabel(time: number) {
  const date = new Date(time),
    now = new Date();
  if (date.toDateString() === now.toDateString())
    return date.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
  const yesterday = new Date();
  yesterday.setDate(now.getDate() - 1);
  if (date.toDateString() === yesterday.toDateString()) return "yesterday";
  return date.toLocaleDateString([], {
    month: "short",
    day: "numeric",
    ...(date.getFullYear() !== now.getFullYear() ? { year: "numeric" } : {}),
  });
}
export function QuickOpen(props: Props) {
  const [query, setQuery] = createSignal("");
  const [selected, setSelected] = createSignal<string | null>(null);
  const [scrollTop, setScrollTop] = createSignal(0);
  let input!: HTMLInputElement, list!: HTMLDivElement;
  const hits = createMemo(() =>
    searchNotes(props.notes, query(), props.access, props.current),
  );
  const active = createMemo(
    () => hits().find((h) => h.note.path === selected()) ?? hits()[0],
  );
  const activePath = createMemo(() => active()?.note.path);
  const start = createMemo(() => Math.max(0, Math.floor(scrollTop() / 61) - 4));
  const visible = createMemo(() => hits().slice(start(), start() + 18));
  onMount(() => input.focus());
  createEffect(() => {
    query();
    setSelected(null);
    if (list) list.scrollTop = 0;
    setScrollTop(0);
  });
  createEffect(() => props.onActive(active()));
  createEffect(
    on(activePath, (path) => {
      if (!list || !path) return;
      const index = hits().findIndex((h) => h.note.path === path);
      const top = index * 61;
      if (top < list.scrollTop) list.scrollTop = top;
      else if (top + 61 > list.scrollTop + list.clientHeight)
        list.scrollTop = top + 61 - list.clientHeight + 12;
      setScrollTop(list.scrollTop);
    }),
  );
  function move(delta: number) {
    const all = hits(),
      index = all.findIndex((h) => h === active());
    const next = all[Math.max(0, Math.min(all.length - 1, index + delta))];
    setSelected(next?.note.path ?? null);
  }
  return (
    <div
      class="quick-open-overlay"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) props.onClose();
      }}
    >
      <div
        class="quick-open"
        role="dialog"
        aria-label="Open a note"
        aria-modal="true"
      >
        <input
          ref={input}
          class="quick-open-input"
          placeholder="Search notes…"
          aria-label="Search notes"
          role="combobox"
          aria-expanded="true"
          aria-controls="note-results"
          aria-activedescendant={
            active() ? `note-${hits().indexOf(active()!)}` : undefined
          }
          value={query()}
          onInput={(e) => setQuery(e.currentTarget.value)}
          onKeyDown={(e) => {
            e.stopPropagation();
            if (
              e.key === "ArrowDown" ||
              e.key === "ArrowUp" ||
              e.key === "Tab"
            ) {
              e.preventDefault();
              move(e.key === "ArrowUp" || e.shiftKey ? -1 : 1);
            }
            if (e.key === "Enter") {
              e.preventDefault();
              const hit = active();
              if (hit) props.onSelect(hit, e.metaKey);
            }
            if (e.key === "Escape" || (e.metaKey && e.key === "p")) {
              e.preventDefault();
              props.onClose();
            }
          }}
        />
        <div
          class="quick-open-list"
          ref={list}
          id="note-results"
          role="listbox"
          aria-label="Notes"
          onScroll={(e) => setScrollTop(e.currentTarget.scrollTop)}
        >
          <div
            role="presentation"
            style={{
              "padding-top": `${start() * 61}px`,
              "padding-bottom": `${Math.max(0, hits().length - start() - visible().length) * 61}px`,
            }}
          >
            <For each={visible()}>
              {(hit, index) => (
                <div
                  class="quick-open-item"
                  id={`note-${start() + index()}`}
                  aria-setsize={hits().length}
                  aria-posinset={start() + index() + 1}
                  data-path={hit.note.path}
                  role="option"
                  aria-selected={active()?.note.path === hit.note.path}
                  classList={{
                    selected: active()?.note.path === hit.note.path,
                  }}
                  onMouseMove={() => setSelected(hit.note.path)}
                  onMouseDown={(e) => {
                    e.preventDefault();
                    props.onSelect(hit, e.metaKey);
                  }}
                >
                  <div class="quick-open-copy">
                    <span class="quick-open-title">{hit.note.title}</span>
                    <span class="quick-open-preview">
                      <Show when={hit.match} fallback={hit.excerpt}>
                        {hit.before}
                        <mark>{hit.match}</mark>
                        {hit.after}
                      </Show>
                    </span>
                  </div>
                  <span class="quick-open-date">
                    {dateLabel(hit.note.modified)}
                  </span>
                </div>
              )}
            </For>
          </div>
          <Show when={!hits().length}>
            <div class="quick-open-empty">
              {props.unavailable
                ? "Notebook unavailable. Use Retry opening to try again."
                : props.loading
                ? "Searching your notebook…"
                : query()
                  ? "No matching notes"
                  : "Your next thought starts here."}
            </div>
          </Show>
        </div>
      </div>
    </div>
  );
}
