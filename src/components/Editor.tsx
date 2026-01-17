import { onMount, onCleanup, createEffect } from 'solid-js'
import { EditorState } from '@codemirror/state'
import { EditorView, keymap, highlightActiveLine } from '@codemirror/view'
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands'
import { markdown } from '@codemirror/lang-markdown'
import './Editor.css'

interface EditorProps {
  content: string
  onChange: (content: string) => void
  onNewNote: () => void
  onOpenNote: () => void
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
      },
      '.cm-line': {
        paddingLeft: '32px',  // 52 / 1.618 ≈ 32
        paddingRight: '32px',
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
      },
      '&.cm-focused': {
        outline: 'none',
      },
      '.cm-cursor, .cm-dropCursor': {
        borderLeftColor: 'var(--fg) !important',
      },
      '.cm-selectionBackground': {
        backgroundColor: 'var(--selection) !important',
      },
      '&.cm-focused .cm-selectionBackground': {
        backgroundColor: 'var(--selection) !important',
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
      })
    }
  })

  return <div ref={containerRef} class="editor-container" />
}
