import type { EditorState } from "@codemirror/state";
import { syntaxTree } from "@codemirror/language";
import { hoverTooltip } from "@codemirror/view";

export interface NoteLink {
  from: number;
  to: number;
  url: string;
  editFrom: number;
  editTo: number;
  labelFrom?: number;
  labelTo?: number;
  tailFrom?: number;
}

export function linkDestination(
  source: string,
  markdownDestination = false,
): string | null {
  let text = source.replace(/^<|>$/g, "");
  if (markdownDestination) {
    text = text.replace(/\\([\\()[\]<>])/g, "$1").replace(/&amp;/g, "&");
  }
  if (/^www\./i.test(text)) text = "https://" + text;
  try {
    const url = new URL(text);
    return ["https:", "http:"].includes(url.protocol) ? url.href : null;
  } catch {
    return null;
  }
}

/** Use the editor's Markdown parser so parentheses, punctuation, and code spans
 * have the same boundaries as the text being edited. No URL fetches are made. */
export function documentLinks(
  state: EditorState,
  from: number,
  to: number,
): NoteLink[] {
  const links: NoteLink[] = [];
  syntaxTree(state).iterate({
    from,
    to,
    enter(ref) {
      if (ref.name !== "URL") return;
      const node = ref.node,
        parent = node.parent;
      const source = state.sliceDoc(node.from, node.to);
      const url = linkDestination(source, parent?.name === "Link");
      const angled = source.startsWith("<") && source.endsWith(">");
      const editFrom = node.from + (angled ? 1 : 0);
      const editTo = node.to - (angled ? 1 : 0);
      if (!url) return;
      if (parent?.name === "Link") {
        const marks = parent.getChildren("LinkMark");
        if (
          marks.length >= 4 &&
          state.doc.lineAt(parent.from).number ===
            state.doc.lineAt(parent.to).number
        ) {
          links.push({
            from: parent.from,
            to: parent.to,
            url,
            editFrom,
            editTo,
            labelFrom: marks[0].to,
            labelTo: marks[1].from,
            tailFrom: marks[2].from,
          });
          return;
        }
      }
      links.push({
        from: node.from,
        to: node.to,
        url,
        editFrom,
        editTo,
      });
    },
  });
  return links;
}

export const linkAttributes = (link: NoteLink) => ({
  "data-url": link.url,
  "data-link-from": String(link.from),
  "data-link-to": String(link.to),
  "data-edit-from": String(link.editFrom),
  "data-edit-to": String(link.editTo),
});

/** Keep a source position for every visible character. Using the source here
 * also means escaped Markdown and addresses containing spaces remain editable
 * at the exact character the user clicked. */
export function compactLinkSource(link: NoteLink, source: string) {
  let text = "";
  const offsets = [link.editFrom];
  for (const part of source.matchAll(/\\[\\()[\]<>]|&amp;|[\s\S]/gu)) {
    const raw = part[0];
    const value =
      link.labelFrom === undefined
        ? raw
        : raw === "&amp;"
          ? "&"
          : raw.startsWith("\\") && raw.length === 2
            ? raw.slice(1)
            : raw;
    text += value;
    for (let i = 1; i <= value.length; i++)
      offsets.push(
        link.editFrom + part.index! + (i === value.length ? raw.length : i),
      );
  }
  const schemeLength = /^https?:\/\//i.exec(text)?.[0].length ?? 0;
  const rest = text.slice(schemeLength);
  const authorityEnd = schemeLength + rest.search(/[/?#]|$/);
  const hostFrom = Math.max(
    schemeLength,
    text.lastIndexOf("@", authorityEnd - 1) + 1,
  );
  const pathEnd = authorityEnd + text.slice(authorityEnd).search(/[?#]|$/);
  const path = text.slice(authorityEnd, pathEnd);
  const visiblePath = path === "/" ? "" : Array.from(path).slice(0, 16).join("");
  const visibleTo = authorityEnd + visiblePath.length;
  const hidden =
    visiblePath !== (path === "/" ? "" : path) || pathEnd < text.length;
  return {
    text: text.slice(hostFrom, visibleTo),
    offsets: offsets.slice(hostFrom, visibleTo + 1),
    suffix: hidden ? (visiblePath ? "…" : "/…") : "",
  };
}

/** Browser caret APIs often treat replacement widgets as indivisible. Measure
 * the actual text instead, including wrapped fragments, before revealing it. */
export function compactLinkCursor(target: HTMLElement, event: MouseEvent) {
  const fixed = (event.target as HTMLElement).closest<HTMLElement>(
    "[data-edit-position]",
  );
  if (fixed) return Number(fixed.dataset.editPosition);
  const text = target.querySelector<HTMLElement>("[data-compact-text]");
  const node = text?.firstChild;
  if (!text || !node) return Number(target.dataset.editTo);
  const offsets: number[] = JSON.parse(text.dataset.sourceOffsets!);
  const range = document.createRange();
  let closest = { distance: Infinity, position: offsets[0] };
  let index = 0;
  for (const character of node.textContent ?? "") {
    range.setStart(node, index);
    range.setEnd(node, index + character.length);
    for (const rect of range.getClientRects()) {
      const dy = Math.max(rect.top - event.clientY, event.clientY - rect.bottom, 0);
      const right = event.clientX >= (rect.left + rect.right) / 2;
      const dx = Math.abs(event.clientX - (right ? rect.right : rect.left));
      const distance = dx * dx + dy * dy;
      if (distance < closest.distance)
        closest = {
          distance,
          position: offsets[index + (right ? character.length : 0)],
        };
    }
    index += character.length;
  }
  return closest.position;
}

export const linkPreview = hoverTooltip(
  (view, pos) => {
    const line = view.state.doc.lineAt(pos);
    const link = documentLinks(view.state, line.from, line.to).find(
      (link) => pos >= link.from && pos <= link.to,
    );
    if (!link) return null;
    return {
      pos: link.from,
      end: link.to,
      above: false,
      create() {
        const dom = document.createElement("div");
        dom.className = "link-preview";
        dom.setAttribute("role", "tooltip");
        const address = dom.appendChild(document.createElement("div"));
        address.className = "link-preview-address";
        address.textContent = link.url;
        const hint = dom.appendChild(document.createElement("div"));
        hint.className = "link-preview-hint";
        hint.textContent = "⌘-click to open · Click to edit";
        return { dom, offset: { x: 0, y: 6 } };
      },
    };
  },
  { hoverTime: 300, hideOnChange: true },
);
