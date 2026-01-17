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
      '.cm-cursor, .cm-dropCursor': {
        borderLeftColor: 'var(--fg) !important',
        borderLeftWidth: '2px !important',
        height: '1.4em !important',
      },
      '@keyframes cm-blink': {
        '0%, 100%': { opacity: '1' },
        '50%': { opacity: '0' },
      },
      '&.cm-focused .cm-cursor': {
        animation: 'cm-blink 0.4s steps(1) infinite',
      },
      '.cm-selectionBackground, .cm-content ::selection': {
        backgroundColor: '#EEFF41 !important',
      },
      '&.cm-focused .cm-selectionBackground, &.cm-focused .cm-content ::selection': {
        backgroundColor: '#EEFF41 !important',
      },
      '.cm-selectionLayer .cm-selectionBackground': {
        backgroundColor: '#EEFF41 !important',
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
