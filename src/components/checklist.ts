import { isolateHistory } from "@codemirror/commands";
import { ensureSyntaxTree } from "@codemirror/language";
import { EditorView } from "@codemirror/view";

// A space finishes the shorthand, leaving the cursor ready for the task text.
// Keep this in the typing path so pasted notes retain their exact source.
export const checklistShorthand = EditorView.inputHandler.of(
  (view, from, to, text, insert) => {
    const { state } = view;
    if (
      text !== " " ||
      from !== to ||
      view.composing ||
      state.selection.ranges.length !== 1 ||
      !state.selection.main.empty ||
      state.selection.main.head !== from
    )
      return false;

    const line = state.doc.lineAt(from);
    const match = /^([ \t]*)(?:-[ \t]*)?\[\]$/.exec(
      state.sliceDoc(line.from, from),
    );
    if (!match || insert().isUserEvent("input.type.compose")) return false;

    const tree = ensureSyntaxTree(state, from, 20);
    if (!tree) return false;
    for (let node = tree.resolveInner(from, -1); node; node = node.parent!) {
      if (["FencedCode", "CodeBlock", "InlineCode"].includes(node.name))
        return false;
    }

    const replacement = match[1] + "- [ ] ";
    view.dispatch({
      changes: { from: line.from, to: from, insert: replacement },
      selection: { anchor: line.from + replacement.length },
      annotations: isolateHistory.of("full"),
      userEvent: "input.type",
      scrollIntoView: true,
    });
    return true;
  },
);
