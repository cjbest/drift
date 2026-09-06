import { createSignal, onMount, onCleanup, Show } from "solid-js";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { currentMonitor, getCurrentWindow } from "@tauri-apps/api/window";
import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { Editor } from "./components/Editor";
import type { EditorHandle, Position } from "./components/Editor";
import { Shortcuts } from "./components/Shortcuts";
import { cascadeWindow } from "./notebook/window-placement";
import { QuickOpen } from "./components/QuickOpen";
import { SaveQueue, fresh, dirty, snapshot } from "./notebook/session";
import type { Session, Draft, Saved } from "./notebook/session";
import type { Note, Hit } from "./notebook/search";
import "./App.css";

type Theme = "system" | "light" | "dark";
const readJSON = <T,>(key: string, fallback: T): T => {
  try {
    return JSON.parse(localStorage.getItem(key) ?? "null") ?? fallback;
  } catch {
    return fallback;
  }
};
function App() {
  const [active, setActive] = createSignal<Session>(fresh(), { equals: false });
  const [ready, setReady] = createSignal(false),
    [quick, setQuick] = createSignal(false),
    [shortcuts, setShortcuts] = createSignal(false),
    [notes, setNotes] = createSignal<Note[]>([]);
  const [hydrating, setHydrating] = createSignal(false),
    [error, setError] = createSignal(""),
    [notice, setNotice] = createSignal("");
  const [retryKind, setRetryKind] = createSignal<"save" | "notebook">("save");
  const [catalogueUnavailable, setCatalogueUnavailable] = createSignal(false);
  let pendingOpen: { path: string; id: string } | undefined;
  let retryOpenPath: string | undefined;
  const [scrolled, setScrolled] = createSignal(false),
    [access, setAccess] = createSignal<Record<string, number>>({});
  const [match, setMatch] = createSignal<
      { from: number; length: number } | undefined
    >(),
    [restore, setRestore] = createSignal<Position>();
  const [theme, setTheme] = createSignal<Theme>(
    readJSON("appearance", "system"),
  );
  const sessions = new Map<string, Session>(),
    positions = new Map<string, Position>();
  const appWindow = getCurrentWindow();
  let activeHit: Hit | undefined;
  let editor: EditorHandle | undefined,
    prefix = "",
    timer: ReturnType<typeof setTimeout> | undefined,
    noticeTimer: ReturnType<typeof setTimeout> | undefined;
  let refreshing: Promise<void> | undefined,
    navigating = false,
    disposed = false,
    scanVersion = 0,
    indexRun = 0;
  const cleanup: (() => void)[] = [];
  let finishBoot!: () => void;
  const booted = new Promise<void>((resolve) => {
    finishBoot = resolve;
  });
  let presented = false,
    leaving = false,
    quitTask: Promise<void> | undefined,
    presentation: Promise<void> | undefined;
  function presentWindow() {
    if (presented) return Promise.resolve();
    if (presentation) return presentation;
    presentation = (async () => {
      // Font loading works while hidden; animation frames can be suspended.
      await document.fonts.load("italic 32px Newsreader").catch(() => {});
      if (leaving) return;
      presented = await invoke<boolean>("window_ready", {
        dark: getComputedStyle(document.body).colorScheme === "dark",
      });
    })()
      .catch(report)
      .finally(() => {
        presentation = undefined;
      });
    return presentation;
  }
  async function resumeAfterQuit() {
    leaving = false;
    quitTask = undefined;
    await booted;
    await presentWindow();
    void refresh();
  }
  function requestQuit() {
    if (quitTask) return quitTask;
    leaving = true;
    indexRun++;
    clearTimeout(timer);
    quitTask = (async () => {
      await booted;
      try {
        await Promise.all(
          Array.from(new Set([...sessions.values(), active()]), (s) =>
            queue.flush(s),
          ),
        );
        if (prefix)
          storage("last-note", pendingOpen ?? { path: active().path, id: active().id });
        await invoke("quit_ready", { label: appWindow.label });
      } catch (e) {
        report("Could not finish saving. Drift will stay open: " + e);
        await invoke("cancel_quit");
      }
    })();
    return quitTask;
  }
  function report(e: unknown) {
    console.error(e);
    setRetryKind("save");
    setError(String(e));
  }
  function reportNotebook(e: unknown) {
    console.error(e);
    setRetryKind("notebook");
    setError(String(e));
  }
  async function retryNotebook() {
    const path = pendingOpen?.path ?? retryOpenPath;
    const version = scanVersion;
    // Access can return while the remembered note is still unavailable. Refill
    // the notebook immediately instead of waiting for that independent read.
    const catalogue = refresh();
    if (path) await openFile(path);
    await catalogue;
    if (version !== scanVersion) await refresh();
  }
  function flash(message: string) {
    setNotice(message);
    clearTimeout(noticeTimer);
    noticeTimer = setTimeout(() => setNotice(""), 5000);
  }
  function storage(key: string, value: unknown) {
    localStorage.setItem(prefix + key, JSON.stringify(value));
  }
  function checkpoint(s: Session) {
    if (!prefix) return;
    if (dirty(s)) storage("draft:" + s.id, snapshot(s));
    else localStorage.removeItem(prefix + "draft:" + s.id);
    if (s === active() && !pendingOpen)
      storage("window:" + appWindow.label, { id: s.id, path: s.path });
  }
  function applyTheme(mode: Theme) {
    setTheme(mode);
    document.documentElement.dataset.theme = mode;
    localStorage.setItem("appearance", JSON.stringify(mode));
  }
  function toggleTheme() {
    const dark =
      theme() === "dark" ||
      (theme() === "system" &&
        matchMedia("(prefers-color-scheme: dark)").matches);
    applyTheme(dark ? "light" : "dark");
  }
  applyTheme(theme());
  const queue = new SaveQueue(
    (draft) => invoke<Saved>("save_note", { draft }),
    checkpoint,
    (s, conflict) => {
      if (s === active()) setActive(s);
      if (s === active())
        void invoke("claim_note", {
          path: s.path,
          label: appWindow.label,
        }).catch(report);
      scanVersion++;
      setNotes((all) => {
        const next = all.filter((n) => n.path !== s.path);
        if (s.path)
          next.unshift({
            path: s.path,
            title: s.path.slice(0, -3),
            text: s.baseline ?? "",
            modified: Date.now(),
            size: s.text.length,
          });
        return next;
      });
      if (conflict)
        flash(
          "Another version changed. Your writing was saved in a separate conflict note.",
        );
      void refresh();
    },
  );
  function changed(text: string) {
    pendingOpen = undefined;
    const s = active();
    s.text = text;
    s.revision++;
    setActive(s);
    try {
      checkpoint(s);
    } catch (e) {
      report("Could not keep a recovery draft: " + e);
    }
    clearTimeout(timer);
    timer = setTimeout(() => void save(), 450);
  }
  async function save() {
    clearTimeout(timer);
    try {
      await queue.flush(active());
      if (retryKind() === "save") setError("");
      return true;
    } catch (e) {
      report("Your writing is still here. Saving failed: " + e);
      return false;
    }
  }
  function storePosition(p: Position) {
    positions.set(active().id, p);
    if (prefix && active().path)
      try {
        storage("position:" + active().path, p);
      } catch {}
  }
  function focus() {
    setQuick(false);
    editor?.focus();
  }
  async function activate(s: Session, hit?: Hit) {
    sessions.set(s.id, s);
    setMatch(undefined);
    setRestore(
      positions.get(s.id) ??
        (s.path
          ? readJSON(prefix + "position:" + s.path, undefined)
          : undefined),
    );
    setActive(s);
    checkpoint(s);
    setQuick(false);
    if (s.path) {
      const next = { ...access(), [s.path]: Date.now() };
      setAccess(next);
      storage("access", next);
    }
    await invoke("claim_note", { path: s.path, label: appWindow.label });
    if (
      hit &&
      hit.from >= 0 &&
      !hit.note.title
        .toLocaleLowerCase()
        .includes(hit.match.toLocaleLowerCase())
    )
      setMatch({ from: hit.from, length: hit.length });
  }
  async function openFile(path: string, hit?: Hit) {
    if (navigating) return;
    navigating = true;
    try {
      if (!(await save())) return;
      const other = await invoke<string | null>("window_for_note", { path });
      if (other && other !== appWindow.label) {
        await invoke("focus_note_window", { label: other });
        focus();
        return;
      }
      const text = await invoke<string>("read_note", { path });
      let s = Array.from(sessions.values()).find((s) => s.path === path);
      if (!s) s = { ...fresh(), path, text, baseline: text };
      else if (!dirty(s)) {
        s.text = text;
        s.baseline = text;
      }
      pendingOpen = undefined;
      retryOpenPath = undefined;
      await activate(s, hit);
      if (retryKind() === "notebook") setError("");
    } catch (e) {
      retryOpenPath = path;
      reportNotebook("Could not open this note: " + e);
    } finally {
      navigating = false;
    }
  }
  async function newNote() {
    if (navigating) return;
    navigating = true;
    try {
      if (await save()) {
        pendingOpen = undefined;
        retryOpenPath = undefined;
        await activate(fresh());
      }
    } catch (e) {
      report(e);
    } finally {
      navigating = false;
    }
  }
  function toggleShortcuts() {
    if (shortcuts()) {
      setShortcuts(false);
      editor?.focus();
    } else {
      setQuick(false);
      setShortcuts(true);
    }
  }
  async function openNewWindow(path?: string) {
    if (path) {
      try {
        const existing = await invoke<string | null>("window_for_note", {
          path,
        });
        if (existing) {
          await invoke("focus_note_window", { label: existing });
          return;
        }
      } catch (e) {
        report(e);
        return;
      }
    }
    let placement = {};
    try {
      const [position, size, monitor, factor] = await Promise.all([
        appWindow.outerPosition(),
        appWindow.outerSize(),
        currentMonitor(),
        appWindow.scaleFactor(),
      ]);
      if (monitor) {
        const area = monitor.workArea;
        placement = cascadeWindow(
          {
            x: position.x / factor,
            y: position.y / factor,
            width: size.width / factor,
            height: size.height / factor,
          },
          {
            x: area.position.x / factor,
            y: area.position.y / factor,
            width: area.size.width / factor,
            height: area.size.height / factor,
          },
        );
      }
    } catch (e) {
      report("Could not position the new window: " + e);
    }
    const url = new URL(window.location.href);
    url.search = "";
    if (path) url.searchParams.set("file", path);
    const w = new WebviewWindow("drift-" + crypto.randomUUID(), {
      url: url.href,
      title: await appWindow.title(),
      visible: false,
      width: 900,
      height: 700,
      ...placement,
      minWidth: 400,
      minHeight: 300,
      titleBarStyle: "overlay",
      hiddenTitle: true,
    });
    void w.once("tauri://error", (e) => report(e.payload));
  }
  async function refresh() {
    if (leaving || !presented) return;
    if (refreshing) return refreshing;
    const version = scanVersion;
    refreshing = (async () => {
      const metadata = await invoke<Note[]>("list_notes");
      if (catalogueUnavailable() && !pendingOpen && !retryOpenPath && retryKind() === "notebook") setError("");
      setCatalogueUnavailable(false);
      if (disposed || version !== scanVersion) return;
      const previous = new Map(notes().map((n) => [n.path, n]));
      const next = metadata.map((n) => {
        const old = previous.get(n.path);
        return old && old.modified === n.modified && old.size === n.size
          ? { ...n, text: old.text }
          : n;
      });
      setNotes(next);
      const todo = next.filter((n) => n.text === undefined),
        run = ++indexRun;
      setHydrating(!!todo.length);
      const pending = new Map<string, { text: string; modified: number }>();
      let publication: ReturnType<typeof setTimeout> | undefined;
      const publish = () => {
        clearTimeout(publication);
        publication = undefined;
        if (disposed || run !== indexRun || version !== scanVersion) {
          pending.clear();
          return;
        }
        const batch = new Map(pending);
        pending.clear();
        setNotes((all) =>
          all.map((n) => {
            const body = batch.get(n.path);
            return body && body.modified === n.modified
              ? { ...n, text: body.text }
              : n;
          }),
        );
      };
      // The catalogue paints before any body read. Background indexing never blocks opening.
      const worker = async () => {
        while (todo.length && !disposed && run === indexRun) {
          const note = todo.shift()!;
          try {
            const text = await invoke<string>("read_note", { path: note.path });
            if (run === indexRun && version === scanVersion) {
              pending.set(note.path, { text, modified: note.modified });
              if (pending.size >= 16) publish();
              else if (!publication) publication = setTimeout(publish, 32);
            }
          } catch {
            /* A temporarily unavailable body keeps its filename visible and is retried next scan. */
          }
        }
      };
      void Promise.all(Array.from({ length: 4 }, worker)).finally(() => {
        publish();
        if (run === indexRun) setHydrating(false);
      });
    })()
      .catch((e) => {
        setCatalogueUnavailable(true);
        reportNotebook("Could not read the notebook: " + e);
      })
      .finally(() => {
        refreshing = undefined;
      });
    return refreshing;
  }
  async function externalRefresh() {
    if (!ready() || navigating || leaving || !presented) return;
    if (pendingOpen) {
      void retryNotebook();
      return;
    }
    void refresh();
    const s = active(),
      revision = s.revision,
      path = s.path;
    if (!path || dirty(s)) return;
    try {
      const text = await invoke<string>("read_note", { path });
      if (
        active() === s &&
        s.revision === revision &&
        !dirty(s) &&
        s.path === path &&
        s.text !== text
      ) {
        s.text = text;
        s.baseline = text;
        s.revision++;
        setActive(s);
      }
    } catch (e) {
      if (active() === s && (!retryOpenPath || retryOpenPath === path)) {
        retryOpenPath ??= path;
        reportNotebook(
          "This note is unavailable on disk. Your open copy is still here. " +
            e,
        );
      }
    }
  }
  async function close() {
    leaving = true;
    indexRun++;
    await booted;
    if (await save()) {
      storage("last-note", pendingOpen ?? { path: active().path, id: active().id });
      await appWindow.destroy();
    } else {
      leaving = false;
      void refresh();
    }
  }
  onMount(async () => {
    const bind = async (name: string, action: () => void, all = false) => {
      const off = await listen(name, () => {
        if (all || document.hasFocus()) action();
      });
      cleanup.push(off);
    };
    try {
      await bind(
        "prepare-quit",
        () => {
          void requestQuit();
        },
        true,
      );
      await bind(
        "quit-cancelled",
        () => {
          void resumeAfterQuit();
        },
        true,
      );
      await bind(
        "notebook-access-granted",
        () => {
          void booted.then(() => {
            if (!leaving && !disposed) void retryNotebook();
          });
        },
        true,
      );
      cleanup.push(
        await appWindow.onCloseRequested((e) => {
          e.preventDefault();
          void close();
        }),
      );

      const info = await invoke<{ directory: string; drafts: Draft[]; restoreDrafts: boolean }>(
        "notebook_info",
      );
      prefix = "notebook:" + info.directory + ":";
      setAccess(readJSON(prefix + "access", {}));
      const recovery = new Map<string, Draft>();
      // Recovery belongs to app startup. A newly opened window shares these
      // stores with live editors; importing their drafts would save stale copies.
      if (info.restoreDrafts) {
        for (const d of info.drafts) recovery.set(d.id, d);
        for (let i = 0; i < localStorage.length; i++) {
          const key = localStorage.key(i)!;
          if (key.startsWith(prefix + "draft:")) {
            const d = readJSON<Draft | null>(key, null);
            if (d) recovery.set(d.id, d);
          }
        }
      }
      for (const d of recovery.values())
        sessions.set(d.id, { ...d, revision: 0 });
      const params = new URLSearchParams(location.search),
        requested = params.get("file");
      const last = readJSON<{ path: string | null; id: string } | null>(
        prefix + "window:" + appWindow.label,
        appWindow.label === "main"
          ? readJSON(prefix + "last-note", null)
          : null,
      );
      const recovered = last ? sessions.get(last.id) : undefined;
      let s =
        recovered ??
        (appWindow.label === "main"
          ? Array.from(sessions.values())[0]
          : undefined);
      if (requested || (!s && last?.path)) {
        const path = requested ?? last!.path!;
        const waiting = setTimeout(() => {
          if (!leaving) {
            setNotice("Opening your notebook…");
            void presentWindow();
          }
        }, 750);
        try {
          const text = await invoke<string>("read_note", { path });
          s = {
            ...fresh(),
            id: last?.path === path ? last.id : crypto.randomUUID(),
            path,
            text,
            baseline: text,
          };
        } catch (e) {
          pendingOpen = { path, id: last?.id ?? crypto.randomUUID() };
          reportNotebook("The previous note could not be opened: " + e);
        } finally {
          clearTimeout(waiting);
          if (notice() === "Opening your notebook…") setNotice("");
        }
      }
      if (!s) s = fresh();
      await activate(s);
      setReady(true);
      if (recovery.size)
        flash("Recovered unfinished writing from your last session.");
      await Promise.all([
        bind("menu-shortcuts", toggleShortcuts),
        bind("menu-new-note", () => void newNote()),
        bind("menu-open-note", () => {
          if (quick()) focus();
          else {
            setQuick(true);
            void refresh();
          }
        }),
        bind("menu-new-window", () => openNewWindow()),
        bind("menu-close-window", () => void close()),
        bind("menu-cycle-theme", toggleTheme),
        bind("menu-theme-system", () => applyTheme("system")),
        bind("menu-theme-light", () => applyTheme("light")),
        bind("menu-theme-dark", () => applyTheme("dark")),
        bind("menu-save", () => void save()),
        bind("menu-check", () => {
          if (quick() && activeHit) {
            openNewWindow(activeHit.note.path);
            focus();
          } else editor?.command("check");
        }),
        ...[
          "find",
          "find-next",
          "find-previous",
          "select-line",
          "bullet",
          "checklist",
          "indent",
          "outdent",
        ].map((name) => bind("menu-" + name, () => editor?.command(name))),
      ]);
      const onBlur = () => {
          void save();
          document.body.classList.remove("cmd-held");
        },
        onFocus = () => void externalRefresh();
      const onKey = (e: KeyboardEvent) => {
        if (
          e.type === "keydown" &&
          (e.metaKey || e.ctrlKey) &&
          e.code === "Slash" &&
          !e.shiftKey &&
          !e.altKey
        ) {
          e.preventDefault();
          e.stopPropagation();
          toggleShortcuts();
        }
        if (e.key === "Meta")
          document.body.classList.toggle("cmd-held", e.type === "keydown");
      };
      const onDrag = (e: MouseEvent) => {
        if (
          e.metaKey &&
          e.button === 0 &&
          !(e.target as HTMLElement).closest(
            "[data-url],.link-preview,.quick-open,.cm-search,button,input",
          )
        ) {
          e.preventDefault();
          void appWindow.startDragging();
        }
      };
      window.addEventListener("blur", onBlur);
      window.addEventListener("focus", onFocus);
      window.addEventListener("keydown", onKey, true);
      window.addEventListener("keyup", onKey);
      window.addEventListener("mousedown", onDrag, true);
      const interval = setInterval(() => {
        if (document.hasFocus()) void externalRefresh();
      }, 4000);
      cleanup.push(() => {
        clearInterval(interval);
        window.removeEventListener("blur", onBlur);
        window.removeEventListener("focus", onFocus);
        window.removeEventListener("keydown", onKey, true);
        window.removeEventListener("keyup", onKey);
        window.removeEventListener("mousedown", onDrag, true);
      });
    } catch (e) {
      report(e);
    } finally {
      finishBoot();
    }
    if (leaving) return;
    try {
      await presentWindow();
      if (!presented || leaving) return;
      void refresh();
      for (const other of sessions.values())
        if (other !== active() && dirty(other))
          void queue.flush(other).catch(report);
    } catch (e) {
      report(e);
    }
  });
  onCleanup(() => {
    disposed = true;
    indexRun++;
    clearTimeout(timer);
    clearTimeout(noticeTimer);
    cleanup.forEach((fn) => fn());
  });
  return (
    <div class="app">
      <div class="titlebar" data-tauri-drag-region>
        <span class="titlebar-title" classList={{ visible: scrolled() }}>
          {active()
            .text.split("\n")
            .find((s) => s.trim())
            ?.replace(/^#+\s*/, "") ?? ""}
        </span>
      </div>
      <Show when={ready()}>
        <Editor
          id={active().id}
          content={active().text}
          position={restore()}
          match={match()}
          onChange={changed}
          onPosition={storePosition}
          onReady={(h) => (editor = h)}
          onScrollPastTitle={setScrolled}
          onNewNote={() => void newNote()}
          onOpenNote={() => {
            setQuick(true);
            void refresh();
          }}
          onNewWindow={() => openNewWindow()}
          onToggleTheme={toggleTheme}
          onSystemTheme={() => applyTheme("system")}
          onError={flash}
        />
      </Show>
      <Show when={quick()}>
        <QuickOpen
          onActive={(hit) => (activeHit = hit)}
          notes={notes()}
          access={access()}
          current={active().path}
          loading={hydrating()}
          unavailable={catalogueUnavailable()}
          onClose={focus}
          onSelect={(hit, newWindow) => {
            if (newWindow) {
              focus();
              openNewWindow(hit.note.path);
            } else void openFile(hit.note.path, hit);
          }}
        />
      </Show>
      <Show when={shortcuts()}>
        <Shortcuts
          onClose={() => {
            setShortcuts(false);
            editor?.focus();
          }}
        />
      </Show>
      <Show when={error()}>
        <div class="problem" role="alert">
          <span>{error()}</span>
          <button onClick={() => void (retryKind() === "notebook" ? retryNotebook() : save())}>
            {retryKind() === "notebook" ? "Retry opening" : "Retry save"}
          </button>
          <button onClick={() => setError("")} aria-label="Dismiss error">
            ×
          </button>
        </div>
      </Show>
      <Show when={notice()}>
        <div class="notice" role="status">
          {notice()}
        </div>
      </Show>
    </div>
  );
}
export default App;
