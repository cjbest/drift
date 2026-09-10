import { EditorSelection } from "@codemirror/state";
import { Direction, layer, RectangleMarker } from "@codemirror/view";

interface TextRow {
  top: number;
  bottom: number;
  spans: { left: number; right: number }[];
}

// Native text ranges already account for wrapping, bidi, and inline formatting.
// Measure a logical line at once instead of hit-testing both ends of every
// visual row (which repeatedly searches the same wrapped text during a drag).
function textRows(range: Range): TextRow[] {
  const rows: TextRow[] = [];
  const rects = Array.from(range.getClientRects()).sort(
    (a, b) => a.top - b.top || a.left - b.left,
  );
  for (const rect of rects) {
    // Ignore zero-height list spacers, retaining zero-width text/whitespace.
    if (!rect.height) continue;
    let row = rows[rows.length - 1];
    if (!row || rect.top >= row.bottom) {
      row = { top: rect.top, bottom: rect.bottom, spans: [] };
      rows.push(row);
    } else {
      row.top = Math.min(row.top, rect.top);
      row.bottom = Math.max(row.bottom, rect.bottom);
    }
    row.spans.push({ left: rect.left, right: rect.right });
  }
  return rows;
}

/** Keep each visual row at its text height, even when a selection crosses a
 * newline or soft wrap. Preserve the separate CodeMirror caret layer. */
export const steadySelection = layer({
  above: false,
  class: "drift-selectionLayer",
  update: (u) => u.docChanged || u.selectionSet || u.viewportChanged,
  markers(view) {
    if (view.state.selection.ranges.every((range) => range.empty)) return [];
    const markers: RectangleMarker[] = [];
    const content = view.contentDOM.getBoundingClientRect();
    const scroll = view.scrollDOM.getBoundingClientRect();
    const baseLeft =
      (view.textDirection === Direction.LTR
        ? scroll.left
        : scroll.right - view.scrollDOM.clientWidth * view.scaleX) -
      view.scrollDOM.scrollLeft * view.scaleX;
    const baseTop = scroll.top - view.scrollDOM.scrollTop * view.scaleY;
    const line = view.contentDOM.querySelector(".cm-line");
    const style = line && getComputedStyle(line);
    const left = content.left + (style ? parseFloat(style.paddingLeft) : 0);
    const right = content.right - (style ? parseFloat(style.paddingRight) : 0);
    const domRange = document.createRange();
    for (const range of view.state.selection.ranges) {
      if (range.empty) continue;
      for (const visible of view.visibleRanges) {
        let pos = Math.max(range.from, visible.from);
        const limit = Math.min(range.to, visible.to);
        while (pos < limit) {
          const docLine = view.state.doc.lineAt(pos);
          const to = Math.min(docLine.to, limit);
          const start = view.domAtPos(pos),
            end = view.domAtPos(to);
          domRange.setStart(start.node, start.offset);
          domRange.setEnd(end.node, end.offset);
          const rows = textRows(domRange);
          if (!rows.length) {
            // Empty lines still show the selected newline at their text height.
            for (const caret of RectangleMarker.forRange(
              view,
              "cm-selectionBackground",
              EditorSelection.cursor(pos, 1),
            )) {
              rows.push({
                top: caret.top + baseTop,
                bottom: caret.top + baseTop + caret.height,
                spans: [
                  {
                    left: caret.left + baseLeft,
                    right: caret.left + baseLeft,
                  },
                ],
              });
            }
          }
          const ltr = view.textDirectionAt(pos) === Direction.LTR;
          for (let i = 0; i < rows.length; i++) {
            const row = rows[i];
            row.spans.sort((a, b) => a.left - b.left);
            // Inline ancestors may repeat their text's rectangles. Merge only
            // overlapping spans, keeping the gaps in partial bidi selections.
            const spans: TextRow["spans"] = [];
            for (const span of row.spans) {
              const previous = spans[spans.length - 1];
              if (previous && span.left <= previous.right)
                previous.right = Math.max(previous.right, span.right);
              else spans.push({ ...span });
            }
            if (i < rows.length - 1 || range.to > docLine.to) {
              // A selected line ending fills the width without joining leading.
              if (ltr) {
                const last = spans[spans.length - 1];
                last.right = Math.max(right, last.right);
              }
              else spans[0].left = Math.min(left, spans[0].left);
            }
            for (const span of spans)
              markers.push(
                new RectangleMarker(
                  "cm-selectionBackground",
                  span.left - baseLeft,
                  row.top - baseTop,
                  span.right - span.left,
                  row.bottom - row.top,
                ),
              );
          }
          pos = docLine.to + 1;
        }
      }
    }
    return markers;
  },
});
