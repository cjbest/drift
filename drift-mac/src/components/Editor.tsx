import { onMount, onCleanup, createEffect, createSignal } from "solid-js";
import { open } from "@tauri-apps/plugin-shell";
import { Annotation, EditorState, Transaction } from "@codemirror/state";
import {
  EditorView,
  keymap,
  drawSelection,
  scrollPastEnd,
  closeHoverTooltips,
  hasHoverTooltips,
  tooltips,
} from "@codemirror/view";
import {
  defaultKeymap,
  history,
  historyKeymap,
  indentMore,
  indentLess,
  undo,
  redo,
  selectLine,
} from "@codemirror/commands";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import {
  search,
  searchKeymap,
  openSearchPanel,
  closeSearchPanel,
  findNext,
  findPrevious,
  getSearchQuery,
  setSearchQuery,
  SearchQuery,
} from "@codemirror/search";
import { notebookMarkdown, toggleList, toggleCheckbox } from "./markdown";
import { compactLinkCursor, linkPreview } from "./links";
import { steadySelection } from "./selection";
import { checklistShorthand } from "./checklist";
import "./Editor.css";

export interface Position {
  anchor: number;
  head: number;
  scroll: number;
}
export interface EditorHandle {
  focus: () => void;
  command: (name: string) => void;
  position: () => Position;
}
interface Props {
  id: string;
  content: string;
  position?: Position;
  match?: { from: number; length: number };
  onChange: (text: string) => void;
  onPosition: (position: Position) => void;
  onScrollPastTitle: (scrolled: boolean) => void;
  onReady: (handle: EditorHandle) => void;
  onNewNote: () => void;
  onOpenNote: () => void;
  onNewWindow: () => void;
  onToggleTheme: () => void;
  onSystemTheme: () => void;
  onError: (message: string) => void;
}
const external = Annotation.define<boolean>();
export function Editor(props: Props) {
  let container!: HTMLDivElement,
    view: EditorView | undefined,
    currentId = "";
  const states = new Map<string, { state: EditorState; scroll: number }>();
  const [ready, setReady] = createSignal(false);
  const position = (): Position => ({
    anchor: view?.state.selection.main.anchor ?? 0,
    head: view?.state.selection.main.head ?? 0,
    scroll: view?.scrollDOM.scrollTop ?? 0,
  });
  function customSearch(editor: EditorView) {
    const dom = document.createElement("div");
    dom.className = "cm-search";
    const input = document.createElement("input");
    input.placeholder = "Find in note…";
    input.setAttribute("main-field", "true");
    input.setAttribute("aria-label", "Find in note");
    input.value = getSearchQuery(editor.state).search;
    const count = document.createElement("span");
    count.className = "search-count";
    count.setAttribute("aria-live", "polite");
    const button = (label: string, text: string, action: () => void) => {
      const b = document.createElement("button");
      b.type = "button";
      b.textContent = text;
      b.setAttribute("aria-label", label);
      b.onclick = action;
      return b;
    };
    dom.append(
      input,
      count,
      button("Previous match", "‹", () => findPrevious(editor)),
      button("Next match", "›", () => findNext(editor)),
      button("Close find", "Done", () => {
        closeSearchPanel(editor);
        editor.focus();
      }),
    );
    input.oninput = () => {
      const query = new SearchQuery({ search: input.value, literal: true });
      editor.dispatch({ effects: setSearchQuery.of(query) });
      const match = query.getCursor(editor.state.doc).next();
      if (!match.done)
        editor.dispatch({
          selection: { anchor: match.value.from, head: match.value.to },
          effects: EditorView.scrollIntoView(match.value.from, { y: "center" }),
        });
    };
    input.onkeydown = (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        e.shiftKey ? findPrevious(editor) : findNext(editor);
      }
      if (e.key === "Escape") {
        e.preventDefault();
        closeSearchPanel(editor);
        editor.focus();
      }
    };
    function updateCount() {
      const query = getSearchQuery(editor.state);
      if (!query.search) {
        count.textContent = "";
        return;
      }
      const cursor = query.getCursor(editor.state.doc);
      let total = 0,
        current = 0;
      let found = cursor.next();
      while (!found.done) {
        total++;
        if (found.value.from === editor.state.selection.main.from)
          current = total;
        found = cursor.next();
      }
      count.textContent = current ? `${current}/${total}` : `${total}`;
    }
    updateCount();
    return {
      dom,
      top: true,
      mount() {
        input.focus();
        input.select();
      },
      update: updateCount,
    };
  }
  const commands: Record<string, () => void> = {
    find: () => {
      if (view) openSearchPanel(view);
    },
    "find-next": () => {
      if (view) findNext(view);
    },
    "find-previous": () => {
      if (view) findPrevious(view);
    },
    undo: () => {
      if (view) undo(view);
    },
    redo: () => {
      if (view) redo(view);
    },
    "select-line": () => {
      if (view) selectLine(view);
    },
    bullet: () => {
      if (view) toggleList("bullet")(view);
    },
    checklist: () => {
      if (view) toggleList("check")(view);
    },
    check: () => {
      if (view) toggleCheckbox(view);
    },
    indent: () => {
      if (view) indentMore(view);
    },
    outdent: () => {
      if (view) indentLess(view);
    },
  };
  const extensions = () => [
    history(),
    markdown({ base: markdownLanguage }),
    checklistShorthand,
    notebookMarkdown,
    EditorView.lineWrapping,
    scrollPastEnd(),
    EditorView.contentAttributes.of({
      "aria-label": "Note text",
      spellcheck: "true",
    }),
    EditorView.scrollMargins.of(() => ({ top: 52, bottom: 64 })),
    drawSelection({ cursorBlinkRate: 0 }),
    steadySelection,
    linkPreview,
    tooltips({
      tooltipSpace: () => ({
        left: 12,
        right: document.documentElement.clientWidth - 12,
        top: 44,
        bottom: document.documentElement.clientHeight - 12,
      }),
    }),
    search({ top: true, createPanel: customSearch }),
    keymap.of([
      {
        key: "Escape",
        run: (view) => {
          if (!hasHoverTooltips(view.state)) return false;
          view.dispatch({ effects: closeHoverTooltips });
          return true;
        },
      },
      {
        key: "Mod-n",
        run: () => {
          props.onNewNote();
          return true;
        },
      },
      {
        key: "Mod-p",
        run: () => {
          props.onOpenNote();
          return true;
        },
      },
      {
        key: "Mod-Shift-n",
        run: () => {
          props.onNewWindow();
          return true;
        },
      },
      {
        key: "Mod-d",
        run: () => {
          props.onToggleTheme();
          return true;
        },
      },
      {
        key: "Mod-Shift-d",
        run: () => {
          props.onSystemTheme();
          return true;
        },
      },
      { key: "Mod-l", run: selectLine },
      { key: "Tab", run: indentMore },
      { key: "Shift-Tab", run: indentLess },
      { key: "Mod-Shift-8", run: toggleList("bullet") },
      { key: "Mod-Shift-l", run: toggleList("check") },
      { key: "Mod-Enter", run: toggleCheckbox },
      ...defaultKeymap,
      ...historyKeymap,
      ...searchKeymap,
    ]),
    EditorView.updateListener.of((u) => {
      if (u.docChanged && !u.transactions.some((t) => t.annotation(external)))
        props.onChange(u.state.doc.toString());
      if (u.selectionSet) props.onPosition(position());
    }),
    EditorView.domEventHandlers({
      mousedown: (e, v) => {
        const target = (e.target as HTMLElement).closest<HTMLElement>(
          "[data-url]",
        );
        if (e.button === 0 && target?.dataset.url) {
          if (e.metaKey && !e.shiftKey && !e.altKey && !e.ctrlKey) {
            e.preventDefault();
            void open(target.dataset.url).catch((error) =>
              props.onError("Could not open this link: " + error),
            );
            return true;
          }
          if (
            target.dataset.compactLink &&
            !e.metaKey &&
            !e.shiftKey &&
            !e.altKey &&
            !e.ctrlKey
          ) {
            e.preventDefault();
            const pos = compactLinkCursor(target, e);
            v.focus();
            v.dispatch({ selection: { anchor: pos } });
            return true;
          }
        }
        if ((e.target as HTMLElement).closest(".checkbox-marker")) {
          e.preventDefault();
          const pos = v.posAtCoords({ x: e.clientX, y: e.clientY });
          if (pos !== null) {
            const old = v.state.selection;
            v.dispatch({ selection: { anchor: pos } });
            toggleCheckbox(v);
            v.dispatch({ selection: old });
          }
          return true;
        }
        return false;
      },
    }),
    EditorView.theme({
      "&": {
        height: "100%",
        fontSize: "18px",
        backgroundColor: "var(--bg)",
        color: "var(--fg)",
      },
      "&.cm-focused": { outline: "none" },
      ".cm-gutters": { display: "none" },
      ".cm-content": {
        fontFamily: '"SF Mono", Menlo, Monaco, monospace',
        paddingTop: "48px",
        paddingBottom: "24px",
        lineHeight: "1.65",
      },
      ".cm-line": { padding: "0" },
      ".cm-scroller": {
        overflow: "auto",
        paddingLeft: "max(32px, calc((100% - 900px) / 2))",
        paddingRight: "max(32px, calc((100% - 900px) / 2))",
      },
    }),
  ];
  onMount(() => {
    view = new EditorView({
      state: EditorState.create({
        doc: props.content,
        extensions: extensions(),
      }),
      parent: container,
    });
    const scroll = () => {
      props.onScrollPastTitle((view?.scrollDOM.scrollTop ?? 0) > 34);
      props.onPosition(position());
    };
    view.scrollDOM.addEventListener("scroll", scroll);
    props.onReady({
      focus: () => view?.focus(),
      command: (name) => commands[name]?.(),
      position,
    });
    setReady(true);
  });
  createEffect(() => {
    if (!ready() || !view) return;
    const id = props.id,
      text = props.content;
    if (id !== currentId) {
      if (currentId)
        states.set(currentId, {
          state: view.state,
          scroll: view.scrollDOM.scrollTop,
        });
      currentId = id;
      const cached = states.get(id),
        same = cached?.state.doc.toString() === text;
      const pos = props.position,
        clamp = (n: number) => Math.max(0, Math.min(n, text.length));
      view.setState(
        same
          ? cached!.state
          : EditorState.create({
              doc: text,
              selection: {
                anchor: clamp(pos?.anchor ?? 0),
                head: clamp(pos?.head ?? 0),
              },
              extensions: extensions(),
            }),
      );
      const targetScroll = same ? cached!.scroll : pos?.scroll ?? 0;
      view.scrollDOM.scrollTop = targetScroll;
      requestAnimationFrame(() => {
        if (view && currentId === id && !props.match) {
          view.scrollDOM.scrollTop = targetScroll;
          props.onScrollPastTitle(targetScroll > 34);
        }
      });
      view.focus();
    } else if (view.state.doc.toString() !== text) {
      const head = Math.min(view.state.selection.main.head, text.length),
        scroll = view.scrollDOM.scrollTop;
      view.dispatch({
        changes: { from: 0, to: view.state.doc.length, insert: text },
        selection: { anchor: head },
        annotations: [external.of(true), Transaction.addToHistory.of(false)],
      });
      view.scrollDOM.scrollTop = scroll;
    }
  });
  createEffect(() => {
    if (!ready() || !view) return;
    const match = props.match;
    if (match && match.from >= 0) {
      const id = currentId;
      requestAnimationFrame(() => {
        if (!view || id !== currentId) return;
        const from = Math.min(match.from, view.state.doc.length),
          to = Math.min(from + match.length, view.state.doc.length);
        view.dispatch({
          selection: { anchor: from, head: to },
          effects: EditorView.scrollIntoView(from, { y: "center" }),
        });
      });
    }
  });
  onCleanup(() => view?.destroy());
  return <div ref={container} class="editor-container" />;
}
