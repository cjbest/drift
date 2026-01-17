import { onMount, onCleanup, createEffect } from 'solid-js'
import { EditorState, RangeSetBuilder } from '@codemirror/state'
import { EditorView, keymap, highlightActiveLine, ViewPlugin, Decoration, drawSelection } from '@codemirror/view'
import type { DecorationSet } from '@codemirror/view'
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands'
import { markdown } from '@codemirror/lang-markdown'
import './Editor.css'

// Custom selection highlighting that wraps text tightly (Sublime-style)
const selectionMark = Decoration.mark({ class: 'selection-highlight' })

const selectionHighlighter = ViewPlugin.fromClass(class {
  decorations: DecorationSet

  constructor(view: EditorView) {
    this.decorations = this.buildDecorations(view)
  }

  update(update: any) {
    if (update.selectionSet || update.docChanged || update.viewportChanged) {
      this.decorations = this.buildDecorations(update.view)
    }
  }

  buildDecorations(view: EditorView): DecorationSet {
    const builder = new RangeSetBuilder<Decoration>()
    const { from, to } = view.state.selection.main

    if (from === to) {
      return builder.finish()
    }

    // Add decorations for each line segment of the selection
    const doc = view.state.doc
    let pos = from

    while (pos < to) {
      const line = doc.lineAt(pos)
      const lineEnd = Math.min(line.to, to)
      const lineStart = Math.max(line.from, pos)

      // Only decorate if there's actual text to highlight on this line
      if (lineStart < lineEnd) {
        builder.add(lineStart, lineEnd, selectionMark)
      }

      // Move to next line
      pos = line.to + 1
    }

    return builder.finish()
  }
}, {
  decorations: v => v.decorations
})

interface EditorProps {
  content: string
  onChange: (content: string) => void
  onNewNote: () => void
  onOpenNote: () => void
  onNewWindow: () => void
  onCycleTheme: () => void
}

export function Editor(props: EditorProps) {
  let containerRef: HTMLDivElement | undefined
  let view: EditorView | undefined

  onMount(() => {
    const theme = EditorView.theme({
      '&': {
        height: '100%',
        fontSize: '18px',
      },
      '.cm-content': {
        fontFamily: '"SF Mono", Menlo, Monaco, "Courier New", monospace',
        paddingTop: '52px',
        paddingBottom: '20px',
        caretColor: 'var(--fg)',
        lineHeight: '1.6',
      },
      '.cm-line': {
        paddingLeft: '0',
        paddingRight: '0',
      },
      '.cm-gutters': {
        display: 'none',
      },
      '.cm-activeLineGutter': {
        backgroundColor: 'transparent',
      },
      '.cm-activeLine': {
        backgroundColor: 'transparent',
      },
      '.cm-scroller': {
        overflow: 'auto',
        paddingLeft: 'max(32px, calc((100% - 900px) / 2))',
        paddingRight: 'max(32px, calc((100% - 900px) / 2))',
      },
      '&.cm-focused': {
        outline: 'none',
      },
    })

    const lightTheme = EditorView.theme({
      '&': {
        backgroundColor: 'var(--bg)',
        color: 'var(--fg)',
      },
    }, { dark: false })

    const updateListener = EditorView.updateListener.of((update) => {
      if (update.docChanged) {
        props.onChange(update.state.doc.toString())
      }
    })

    const appKeymap = keymap.of([
      {
        key: 'Mod-n',
        run: () => {
          props.onNewNote()
          return true
        },
      },
      {
        key: 'Mod-p',
        run: () => {
          props.onOpenNote()
          return true
        },
      },
      {
        key: 'Mod-Shift-n',
        run: () => {
          props.onNewWindow()
          return true
        },
      },
      {
        key: 'Mod-d',
        run: () => {
          props.onCycleTheme()
          return true
        },
      },
    ])

    const state = EditorState.create({
      doc: props.content,
      extensions: [
        theme,
        lightTheme,
        highlightActiveLine(),
        history(),
        appKeymap,
        keymap.of([
          ...defaultKeymap,
          ...historyKeymap,
        ]),
        markdown(),
        updateListener,
        EditorView.lineWrapping,
        selectionHighlighter,
        drawSelection({ cursorBlinkRate: 0 }),
      ],
    })

    view = new EditorView({
      state,
      parent: containerRef!,
    })

    // Focus the editor
    view.focus()
  })

  onCleanup(() => {
    view?.destroy()
  })

  // Update editor content when props.content changes externally
  createEffect(() => {
    const newContent = props.content
    if (view && view.state.doc.toString() !== newContent) {
      view.dispatch({
        changes: {
          from: 0,
          to: view.state.doc.length,
          insert: newContent,
        },
        selection: { anchor: newContent.length },
      })
      view.focus()
    }
  })

  return <div ref={containerRef} class="editor-container" />
}
