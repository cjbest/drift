import { RangeSetBuilder } from "@codemirror/state";
import { syntaxTree } from "@codemirror/language";
import { documentLinks, linkAttributes, compactLinkSource } from "./links";
import type { NoteLink } from "./links";
import {
  Decoration,
  EditorView,
  ViewPlugin,
  WidgetType,
} from "@codemirror/view";
import type { DecorationSet, ViewUpdate } from "@codemirror/view";
import type { Command } from "@codemirror/view";

// A zero-width spacer avoids WKWebView's wrapped text-indent bug.
class BulletSpacer extends WidgetType {
  readonly columns: number;
  constructor(columns: number) {
    super();
    this.columns = columns;
  }
  eq(other: BulletSpacer) {
    return this.columns === other.columns;
  }
  toDOM() {
    const el = document.createElement("span");
    el.style.cssText = `display:inline-block;width:0;margin-left:-${this.columns}ch`;
    return el;
  }
}
class LinkTail extends WidgetType {
  readonly link: NoteLink;
  readonly source: string;
  constructor(link: NoteLink, source: string) {
    super();
    this.link = link;
    this.source = source;
  }
  eq(other: LinkTail) {
    return (
      this.link.url === other.link.url &&
      this.link.from === other.link.from &&
      this.link.to === other.link.to &&
      this.link.editFrom === other.link.editFrom &&
      this.link.editTo === other.link.editTo &&
      this.source === other.source
    );
  }
  toDOM() {
    const el = document.createElement("span");
    el.className = "link-tail note-link";
    for (const [name, value] of Object.entries(linkAttributes(this.link)))
      el.setAttribute(name, value);
    el.dataset.compactLink = "true";
    const compact = compactLinkSource(this.link, this.source);
    const fixed = (text: string, position: number) => {
      const span = el.appendChild(document.createElement("span"));
      span.textContent = text;
      span.dataset.editPosition = String(position);
    };
    if (this.link.labelFrom !== undefined) fixed("(", this.link.editFrom);
    const text = el.appendChild(document.createElement("span"));
    text.dataset.compactText = "true";
    text.dataset.sourceOffsets = JSON.stringify(compact.offsets);
    text.textContent = compact.text;
    if (compact.suffix) fixed(compact.suffix, this.link.editTo);
    if (this.link.labelFrom !== undefined) fixed(")", this.link.editTo);
    el.setAttribute("aria-label", this.link.url);
    return el;
  }
  // Widgets ignore editor mouse handlers by default, which swallowed Cmd-click.
  ignoreEvent() {
    return false;
  }
}
const mark = (className: string, link?: NoteLink) =>
  Decoration.mark({
    class: className,
    attributes: link ? linkAttributes(link) : undefined,
  });

export const notebookMarkdown = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;
    constructor(view: EditorView) {
      this.decorations = this.build(view);
    }
    update(u: ViewUpdate) {
      if (
        u.docChanged ||
        u.viewportChanged ||
        u.selectionSet ||
        u.geometryChanged ||
        syntaxTree(u.startState) !== syntaxTree(u.state)
      )
        this.decorations = this.build(u.view);
    }
    build(view: EditorView) {
      const decos: { from: number; to: number; value: Decoration }[] = [];
      const add = (from: number, to: number, value: Decoration) =>
        decos.push({ from, to, value });
      const doc = view.state.doc,
        selection = view.state.selection.main;
      // An empty document has no visible text ranges yet, but its first line
      // already needs title metrics before the user types the first character.
      add(0, 0, Decoration.line({ attributes: { class: "first-line-title" } }));
      const seen = new Set<number>();
      for (const range of view.visibleRanges) {
        for (
          let i = doc.lineAt(range.from).number;
          i <= doc.lineAt(range.to).number;
          i++
        ) {
          if (seen.has(i)) continue;
          seen.add(i);
          const line = doc.line(i),
            text = line.text;
          const list = text.match(/^(\s*)(?:[-*+] (?:\[[ xX]\] )?|\d+[.)] )/);
          if (list) {
            const columns = list[0].replace(/\t/g, "    ").length;
            // Resolve against this line's font; CodeMirror's default width can
            // be measured from the larger, proportional title.
            add(
              line.from,
              line.from,
              Decoration.line({
                attributes: { style: `margin-left:${columns}ch` },
              }),
            );
            add(
              line.from,
              line.from,
              Decoration.widget({ widget: new BulletSpacer(columns), side: -1 }),
            );
          }
          const checkbox = text.match(/^\s*[-*+] (\[[ xX]\])/);
          if (checkbox) {
            const start = line.from + text.indexOf("[");
            add(start, start + 3, mark("checkbox-marker"));
          }
          const heading = text.match(/^(#{1,6}) (.+)$/);
          if (heading) {
            add(line.from, line.from + heading[1].length, mark("md-marker"));
            add(line.from + heading[1].length + 1, line.to, mark("heading"));
          }
          const quote = text.match(/^(\s*>+)\s?(.*)$/);
          if (quote) {
            add(line.from, line.from + quote[1].length, mark("md-marker"));
            if (quote[2])
              add(line.to - quote[2].length, line.to, mark("italic-text"));
          }
          for (const m of text.matchAll(/\*\*(.+?)\*\*/g))
            add(
              line.from + m.index! + 2,
              line.from + m.index! + 2 + m[1].length,
              mark("bold-text"),
            );
          for (const m of text.matchAll(/(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/g))
            add(
              line.from + m.index! + 1,
              line.from + m.index! + 1 + m[1].length,
              mark("italic-text"),
            );
          for (const link of documentLinks(view.state, line.from, line.to)) {
            const editing = selection.empty
              ? selection.head >= link.from && selection.head <= link.to
              : selection.from < link.to && selection.to > link.from;
            if (
              link.labelFrom !== undefined &&
              link.labelTo !== undefined &&
              link.tailFrom !== undefined
            ) {
              add(link.from, link.labelFrom, mark("md-marker"));
              add(link.labelFrom, link.labelTo, mark("note-link", link));
              if (!editing)
                add(
                  link.tailFrom,
                  link.to,
                  Decoration.replace({
                    widget: new LinkTail(
                      link,
                      doc.sliceString(link.editFrom, link.editTo),
                    ),
                  }),
                );
              else
                add(link.tailFrom, link.to, mark("md-marker note-link", link));
            } else if (link.to - link.from > 60 && !editing) {
              add(
                link.from,
                link.to,
                Decoration.replace({
                  widget: new LinkTail(
                    link,
                    doc.sliceString(link.editFrom, link.editTo),
                  ),
                }),
              );
            } else add(link.from, link.to, mark("note-link", link));
          }
        }
      }
      decos.sort(
        (a, b) =>
          a.from - b.from ||
          a.value.startSide - b.value.startSide ||
          a.to - b.to,
      );
      const builder = new RangeSetBuilder<Decoration>();
      for (const d of decos) builder.add(d.from, d.to, d.value);
      return builder.finish();
    }
  },
  { decorations: (v) => v.decorations },
);

export const toggleList =
  (kind: "bullet" | "check"): Command =>
  (view) => {
    const { from, to } = view.state.selection.main,
      doc = view.state.doc;
    const first = doc.lineAt(from).number,
      last = doc.lineAt(to > from ? to - 1 : to).number;
    const lines = Array.from({ length: last - first + 1 }, (_, i) =>
      doc.line(first + i),
    );
    const rows = lines.map((line) => {
      const prefix = line.text.match(
        /^([ \t]*)([-*+]|\d+[.)])[ \t]+(?:(\[[ xX]\])(?:[ \t]+|$))?/,
      );
      const indent = line.text.match(/^[ \t]*/)?.[0].length ?? 0;
      const style = prefix?.[3]
        ? "check"
        : prefix && /^[-*+]$/.test(prefix[2])
          ? "bullet"
          : undefined;
      return { line, prefix, indent, style };
    });
    const remove = rows.every((row) => row.style === kind);
    const changes = rows.map(({ line, prefix, indent, style }) => ({
      from: line.from + indent,
      to: line.from + (prefix?.[0].length ?? indent),
      // In a mixed selection, retain items already in the requested format,
      // including their checked state. Replace other prefixes instead of stacking.
      insert: remove
        ? ""
        : style === kind
          ? prefix![0].slice(indent)
          : kind === "bullet"
            ? "* "
            : "- [ ] ",
    }));
    const changeSet = view.state.changes(changes);
    view.dispatch({
      changes: changeSet,
      // A cursor at the insertion point belongs after the new list marker.
      selection: view.state.selection.map(changeSet, 1),
      userEvent: "input",
    });
    return true;
  };
export const toggleCheckbox: Command = (view) => {
  const { from, to } = view.state.selection.main;
  const doc = view.state.doc;
  const first = doc.lineAt(from).number;
  // Ending at the start of a line doesn't select that line.
  const last = doc.lineAt(to > from ? to - 1 : to).number;
  const boxes: { from: number; checked: boolean }[] = [];
  for (let i = first; i <= last; i++) {
    const line = doc.line(i);
    const match = line.text.match(/^([ \t]*[-*+] \[)([ xX])\]/);
    if (match)
      boxes.push({
        from: line.from + match[1].length,
        checked: match[2] !== " ",
      });
  }
  if (!boxes.length) return false;
  const check = boxes.some((box) => !box.checked);
  view.dispatch({
    changes: boxes
      .filter((box) => box.checked !== check)
      .map((box) => ({
        from: box.from,
        to: box.from + 1,
        insert: check ? "x" : " ",
      })),
    userEvent: "input",
  });
  return true;
};
