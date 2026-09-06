import { EditorSelection } from "@codemirror/state";
import { Direction, layer, RectangleMarker } from "@codemirror/view";

/** Keep each visual row at its text height, even when a selection crosses a
 * newline or soft wrap. CodeMirror's default layer joins rows through leading,
 * which makes the first row grow as soon as the next row enters the selection.
 * Retain its bidi-aware horizontal measurement and its separate caret layer. */
export const steadySelection = layer({
  above: false,
  class: "drift-selectionLayer",
  update: (u) => u.docChanged || u.selectionSet || u.viewportChanged,
  markers(view) {
    const markers: RectangleMarker[] = [];
    const content = view.contentDOM.getBoundingClientRect();
    const scroll = view.scrollDOM.getBoundingClientRect();
    const baseLeft =
      (view.textDirection === Direction.LTR
        ? scroll.left
        : scroll.right - view.scrollDOM.clientWidth * view.scaleX) -
      view.scrollDOM.scrollLeft * view.scaleX;
    const line = view.contentDOM.querySelector(".cm-line");
    const style = line && getComputedStyle(line);
    const left =
      content.left - baseLeft + (style ? parseFloat(style.paddingLeft) : 0);
    const right =
      content.right - baseLeft - (style ? parseFloat(style.paddingRight) : 0);
    for (const range of view.state.selection.ranges) {
      if (range.empty) continue;
      for (const visible of view.visibleRanges) {
        let pos = Math.max(range.from, visible.from);
        const limit = Math.min(range.to, visible.to);
        while (pos < limit) {
          const docLine = view.state.doc.lineAt(pos);
          const boundary = view.moveToLineBoundary(
            EditorSelection.cursor(pos, 1),
            true,
          ).head;
          const end = Math.min(docLine.to, Math.max(pos, boundary));
          const to = Math.min(end, limit);
          const pieces = Array.from(
            RectangleMarker.forRange(
              view,
              "cm-selectionBackground",
              pos === to
                ? EditorSelection.cursor(pos, 1)
                : EditorSelection.range(pos, to),
            ),
          );
          if (range.to > end && pieces.length) {
            // A selected line ending fills the remaining width without changing height.
            const edge =
              view.textDirectionAt(pos) === Direction.LTR
                ? pieces.reduce((a, b) =>
                    a.left + (a.width ?? 0) > b.left + (b.width ?? 0) ? a : b,
                  )
                : pieces.reduce((a, b) => (a.left < b.left ? a : b));
            const index = pieces.indexOf(edge);
            pieces[index] =
              view.textDirectionAt(pos) === Direction.LTR
                ? new RectangleMarker(
                    "cm-selectionBackground",
                    edge.left,
                    edge.top,
                    Math.max(0, right - edge.left),
                    edge.height,
                  )
                : new RectangleMarker(
                    "cm-selectionBackground",
                    left,
                    edge.top,
                    Math.max(0, edge.left + (edge.width ?? 0) - left),
                    edge.height,
                  );
          }
          markers.push(...pieces);
          // Soft wraps share a document position; hard breaks consume a character.
          const next = end === docLine.to ? end + 1 : end;
          if (next <= pos) break;
          pos = next;
        }
      }
    }
    return markers;
  },
});
