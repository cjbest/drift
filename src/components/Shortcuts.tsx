import { For, onMount } from "solid-js";
import "./Shortcuts.css";

const groups = [
  {
    title: "Notes",
    items: [
      ["Open a note", "⌘ P"],
      ["New note", "⌘ N"],
      ["New window", "⇧ ⌘ N"],
      ["Open search result in a new window", "⌘ Return"],
      ["Close window", "⌘ W"],
    ],
  },
  {
    title: "Writing",
    items: [
      ["Find in this note", "⌘ F"],
      ["Next / previous match", "⌘ G / ⇧ ⌘ G"],
      ["Select line", "⌘ L"],
      ["Toggle bullet list", "⇧ ⌘ 8"],
      ["Toggle checklist", "⇧ ⌘ L"],
      ["Start a checklist", "[] Space"],
      ["Check / uncheck", "⌘ Return"],
      ["Indent / outdent", "Tab / ⇧ Tab"],
    ],
  },
  {
    title: "Around the page",
    items: [
      ["Toggle light / dark", "⌘ D"],
      ["Follow system appearance", "⇧ ⌘ D"],
      ["Open a link", "⌘ click"],
      ["Move the window", "⌘ drag"],
      ["Keyboard shortcuts", "⌘ /"],
    ],
  },
];

export function Shortcuts(props: { onClose: () => void }) {
  let dialog!: HTMLDialogElement;
  onMount(() => dialog.showModal());
  return (
    <dialog
      ref={dialog}
      class="shortcuts"
      aria-labelledby="shortcuts-title"
      onCancel={(e) => {
        e.preventDefault();
        props.onClose();
      }}
      onClick={(e) => {
        if (e.target === dialog) {
          const r = dialog.getBoundingClientRect();
          if (
            e.clientX < r.left ||
            e.clientX > r.right ||
            e.clientY < r.top ||
            e.clientY > r.bottom
          )
            props.onClose();
        }
      }}
    >
      <header>
        <h1 id="shortcuts-title">Keyboard shortcuts</h1>
        <button
          autofocus
          onClick={props.onClose}
          aria-label="Close keyboard shortcuts"
        >
          ×
        </button>
      </header>
      <For each={groups}>
        {(group) => (
          <section>
            <h2>{group.title}</h2>
            <dl>
              <For each={group.items}>
                {([label, keys]) => (
                  <div>
                    <dt>{label}</dt>
                    <dd>
                      <kbd>{keys}</kbd>
                    </dd>
                  </div>
                )}
              </For>
            </dl>
          </section>
        )}
      </For>
      <footer>Escape returns to your note.</footer>
    </dialog>
  );
}
