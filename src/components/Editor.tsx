import { onMount, onCleanup, createEffect, createSignal, Show } from 'solid-js'
import { open } from '@tauri-apps/plugin-shell'
import { ApiKeyDialog } from './ApiKeyDialog'
import { EditorState, RangeSetBuilder } from '@codemirror/state'
import { EditorView, keymap, highlightActiveLine, ViewPlugin, Decoration, drawSelection, WidgetType } from '@codemirror/view'
import type { DecorationSet, ViewUpdate } from '@codemirror/view'
import { defaultKeymap, history, historyKeymap, indentMore, indentLess } from '@codemirror/commands'
import { markdown } from '@codemirror/lang-markdown'
import './Editor.css'

// Custom selection highlighting that wraps text tightly (Sublime-style)
const selectionMark = Decoration.mark({ class: 'selection-highlight' })

// Bold first line (acts as title)
const firstLineMark = Decoration.mark({ class: 'first-line-title' })

// Checkbox decorations for click interaction
const checkboxUnchecked = Decoration.mark({ class: 'checkbox-marker checkbox-unchecked' })
const checkboxChecked = Decoration.mark({ class: 'checkbox-marker checkbox-checked' })

// Heading decorations
const headingMarker = Decoration.mark({ class: 'heading-marker' })
const heading1 = Decoration.mark({ class: 'heading heading-1' })
const heading2 = Decoration.mark({ class: 'heading heading-2' })
const heading3 = Decoration.mark({ class: 'heading heading-3' })

// Blockquote decorations
const blockquoteMarker = Decoration.mark({ class: 'blockquote-marker' })
const blockquoteText = Decoration.mark({ class: 'blockquote-text' })

// Emphasis decorations
const boldText = Decoration.mark({ class: 'bold-text' })
const italicText = Decoration.mark({ class: 'italic-text' })

const headingHighlighter = ViewPlugin.fromClass(class {
  decorations: DecorationSet

  constructor(view: EditorView) {
    this.decorations = this.buildDecorations(view)
  }

  update(update: ViewUpdate) {
    if (update.docChanged || update.viewportChanged) {
      this.decorations = this.buildDecorations(update.view)
    }
  }

  buildDecorations(view: EditorView): DecorationSet {
    const builder = new RangeSetBuilder<Decoration>()
    const doc = view.state.doc

    for (let i = 1; i <= doc.lines; i++) {
      const line = doc.line(i)
      const text = line.text

      // Match headings (# at start of line)
      const match = text.match(/^(#{1,3})\s+(.*)$/)
      if (match) {
        const markerEnd = match[1].length
        const textStart = markerEnd + 1 // skip the space
        const level = match[1].length

        // Style the # markers
        builder.add(line.from, line.from + markerEnd, headingMarker)

        // Style the heading text
        if (match[2].length > 0) {
          const headingDeco = level === 1 ? heading1 : level === 2 ? heading2 : heading3
          builder.add(line.from + textStart, line.to, headingDeco)
        }
      }
    }

    return builder.finish()
  }
}, {
  decorations: v => v.decorations
})

const blockquoteHighlighter = ViewPlugin.fromClass(class {
  decorations: DecorationSet

  constructor(view: EditorView) {
    this.decorations = this.buildDecorations(view)
  }

  update(update: ViewUpdate) {
    if (update.docChanged || update.viewportChanged) {
      this.decorations = this.buildDecorations(update.view)
    }
  }

  buildDecorations(view: EditorView): DecorationSet {
    const builder = new RangeSetBuilder<Decoration>()
    const doc = view.state.doc

    for (let i = 1; i <= doc.lines; i++) {
      const line = doc.line(i)
      const text = line.text

      // Match blockquotes (> at start of line)
      const match = text.match(/^(>+)\s?(.*)$/)
      if (match) {
        const markerEnd = match[1].length
        // Style the > marker(s)
        builder.add(line.from, line.from + markerEnd, blockquoteMarker)
        // Style the quote text
        if (match[2].length > 0) {
          const textStart = markerEnd + (text[markerEnd] === ' ' ? 1 : 0)
          builder.add(line.from + textStart, line.to, blockquoteText)
        }
      }
    }

    return builder.finish()
  }
}, {
  decorations: v => v.decorations
})

const emphasisHighlighter = ViewPlugin.fromClass(class {
  decorations: DecorationSet

  constructor(view: EditorView) {
    this.decorations = this.buildDecorations(view)
  }

  update(update: ViewUpdate) {
    if (update.docChanged || update.viewportChanged) {
      this.decorations = this.buildDecorations(update.view)
    }
  }

  buildDecorations(view: EditorView): DecorationSet {
    const decorations: { from: number; to: number; deco: Decoration }[] = []
    const doc = view.state.doc

    for (let i = 1; i <= doc.lines; i++) {
      const line = doc.line(i)
      const text = line.text

      // Find **bold** patterns - style just the text, not the **
      const boldRegex = /\*\*(.+?)\*\*/g
      let match
      while ((match = boldRegex.exec(text)) !== null) {
        const textStart = line.from + match.index + 2
        const textEnd = textStart + match[1].length
        decorations.push({ from: textStart, to: textEnd, deco: boldText })
      }

      // Find *italic* patterns (but not **) - style just the text, not the *
      const italicRegex = /(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/g
      while ((match = italicRegex.exec(text)) !== null) {
        const textStart = line.from + match.index + 1
        const textEnd = textStart + match[1].length
        decorations.push({ from: textStart, to: textEnd, deco: italicText })
      }
    }

    // Sort by position and add to builder
    decorations.sort((a, b) => a.from - b.from || a.to - b.to)
    const builder = new RangeSetBuilder<Decoration>()
    for (const { from, to, deco } of decorations) {
      builder.add(from, to, deco)
    }

    return builder.finish()
  }
}, {
  decorations: v => v.decorations
})

// Link decorations
const linkBracket = Decoration.mark({ class: 'link-bracket' })
const linkText = Decoration.mark({ class: 'link-text' })
const linkUrlFull = Decoration.mark({ class: 'link-url' })
const bareUrlMark = Decoration.mark({ class: 'bare-url' })

// Helper to truncate URL after domain
function truncateUrl(url: string): string {
  try {
    const parsed = new URL(url)
    return parsed.origin + '/…'
  } catch {
    return url.slice(0, 30) + '…'
  }
}

// Widget for truncated URL display
class TruncatedUrlWidget extends WidgetType {
  constructor(readonly fullUrl: string, readonly displayText: string) {
    super()
  }

  toDOM() {
    const span = document.createElement('span')
    span.className = 'link-url-truncated'
    span.textContent = this.displayText
    span.setAttribute('data-full-url', this.fullUrl)
    return span
  }

  eq(other: TruncatedUrlWidget) {
    return other.fullUrl === this.fullUrl && other.displayText === this.displayText
  }
}

// Plugin for link mark decorations (styling)
const linkStyler = ViewPlugin.fromClass(class {
  decorations: DecorationSet

  constructor(view: EditorView) {
    this.decorations = this.buildDecorations(view)
  }

  update(update: ViewUpdate) {
    if (update.docChanged || update.viewportChanged || update.selectionSet) {
      this.decorations = this.buildDecorations(update.view)
    }
  }

  buildDecorations(view: EditorView): DecorationSet {
    const builder = new RangeSetBuilder<Decoration>()
    const doc = view.state.doc
    const cursorLine = doc.lineAt(view.state.selection.main.head).number

    for (let i = 1; i <= doc.lines; i++) {
      const line = doc.line(i)
      const text = line.text
      const isCurrentLine = i === cursorLine

      // Match markdown links: [text](url)
      const mdLinkRegex = /\[([^\]]+)\]\(([^)]+)\)/g
      let match
      while ((match = mdLinkRegex.exec(text)) !== null) {
        const start = line.from + match.index
        const linkTextContent = match[1]
        const urlContent = match[2]

        // [ bracket
        builder.add(start, start + 1, linkBracket)
        // link text (underlined)
        builder.add(start + 1, start + 1 + linkTextContent.length, linkText)
        // ] bracket
        builder.add(start + 1 + linkTextContent.length, start + 2 + linkTextContent.length, linkBracket)

        // Only show full URL styling when on current line
        if (isCurrentLine) {
          const urlStart = start + 2 + linkTextContent.length
          const urlEnd = urlStart + 2 + urlContent.length
          builder.add(urlStart, urlEnd, linkUrlFull)
        }
      }

      // Match bare URLs (only style when on current line OR short enough)
      const bareUrlRegex = /https?:\/\/[^\s\])<>]+/g
      while ((match = bareUrlRegex.exec(text)) !== null) {
        const url = match[0]
        // Skip if inside markdown link
        const beforeMatch = text.slice(0, match.index)
        if (beforeMatch.match(/\]\($/)) continue

        // Only add mark decoration if on current line or URL is short
        if (isCurrentLine || url.length <= 60) {
          const start = line.from + match.index
          builder.add(start, start + url.length, bareUrlMark)
        }
      }
    }

    return builder.finish()
  }
}, {
  decorations: v => v.decorations
})

// Separate plugin for replace decorations (truncation)
const linkTruncator = ViewPlugin.fromClass(class {
  decorations: DecorationSet

  constructor(view: EditorView) {
    this.decorations = this.buildDecorations(view)
  }

  update(update: ViewUpdate) {
    if (update.docChanged || update.viewportChanged || update.selectionSet) {
      this.decorations = this.buildDecorations(update.view)
    }
  }

  buildDecorations(view: EditorView): DecorationSet {
    const builder = new RangeSetBuilder<Decoration>()
    const doc = view.state.doc
    const cursorLine = doc.lineAt(view.state.selection.main.head).number

    for (let i = 1; i <= doc.lines; i++) {
      const line = doc.line(i)
      const text = line.text
      const isCurrentLine = i === cursorLine

      if (isCurrentLine) continue // Don't truncate on current line

      // Match markdown links: [text](url) - truncate the (url) part
      const mdLinkRegex = /\[([^\]]+)\]\(([^)]+)\)/g
      let match
      while ((match = mdLinkRegex.exec(text)) !== null) {
        const start = line.from + match.index
        const linkTextContent = match[1]
        const urlContent = match[2]
        const urlStart = start + 2 + linkTextContent.length
        const urlEnd = urlStart + 2 + urlContent.length

        builder.add(urlStart, urlEnd, Decoration.replace({
          widget: new TruncatedUrlWidget(urlContent, '(…)')
        }))
      }

      // Match bare URLs - only truncate if > 60 chars
      const bareUrlRegex = /https?:\/\/[^\s\])<>]+/g
      while ((match = bareUrlRegex.exec(text)) !== null) {
        const url = match[0]
        if (url.length <= 60) continue

        // Skip if inside markdown link
        const beforeMatch = text.slice(0, match.index)
        if (beforeMatch.match(/\]\($/)) continue

        const start = line.from + match.index
        builder.add(start, start + url.length, Decoration.replace({
          widget: new TruncatedUrlWidget(url, truncateUrl(url))
        }))
      }
    }

    return builder.finish()
  }
}, {
  decorations: v => v.decorations
})

const checkboxHighlighter = ViewPlugin.fromClass(class {
  decorations: DecorationSet

  constructor(view: EditorView) {
    this.decorations = this.buildDecorations(view)
  }

  update(update: ViewUpdate) {
    if (update.docChanged || update.viewportChanged) {
      this.decorations = this.buildDecorations(update.view)
    }
  }

  buildDecorations(view: EditorView): DecorationSet {
    const builder = new RangeSetBuilder<Decoration>()
    const doc = view.state.doc

    for (let i = 1; i <= doc.lines; i++) {
      const line = doc.line(i)
      const text = line.text

      // Find [ ] or [x] in checkbox pattern
      const uncheckedMatch = text.match(/^- \[ \]/)
      const checkedMatch = text.match(/^- \[x\]/)

      if (uncheckedMatch) {
        // Mark just the [ ] part (positions 2-5)
        builder.add(line.from + 2, line.from + 5, checkboxUnchecked)
      } else if (checkedMatch) {
        // Mark just the [x] part (positions 2-5)
        builder.add(line.from + 2, line.from + 5, checkboxChecked)
      }
    }

    return builder.finish()
  }
}, {
  decorations: v => v.decorations
})

const firstLineHighlighter = ViewPlugin.fromClass(class {
  decorations: DecorationSet

  constructor(view: EditorView) {
    this.decorations = this.buildDecorations(view)
  }

  update(update: ViewUpdate) {
    if (update.docChanged || update.viewportChanged) {
      this.decorations = this.buildDecorations(update.view)
    }
  }

  buildDecorations(view: EditorView): DecorationSet {
    const builder = new RangeSetBuilder<Decoration>()
    const firstLine = view.state.doc.line(1)
    if (firstLine.length > 0) {
      builder.add(firstLine.from, firstLine.to, firstLineMark)
    }
    return builder.finish()
  }
}, {
  decorations: v => v.decorations
})

// Smart cursor hiding:
// - Fades while typing, comes back when idle
// - Fades after 1s with selection (for screenshots)
// - Comes back on cursor movement
const cursorHider = ViewPlugin.fromClass(class {
  timeout: ReturnType<typeof setTimeout> | null = null
  lastCursorPos: number = 0
  lastDocLength: number = 0

  constructor(view: EditorView) {
    this.lastCursorPos = view.state.selection.main.head
    this.lastDocLength = view.state.doc.length
    this.showCursor(view)
  }

  update(update: ViewUpdate) {
    const view = update.view
    const { from, to, head } = view.state.selection.main
    const hasSelection = from !== to
    const cursorMoved = head !== this.lastCursorPos && !update.docChanged
    const line = view.state.doc.lineAt(head)
    const textBeforeCursor = view.state.doc.sliceString(line.from, head)
    const onlyWhitespaceBefore = textBeforeCursor.trim() === ''
    const docLength = view.state.doc.length
    const isDeleting = docLength < this.lastDocLength

    this.lastCursorPos = head
    this.lastDocLength = docLength

    // Clear existing timeout
    if (this.timeout) {
      clearTimeout(this.timeout)
      this.timeout = null
    }

    // Show cursor immediately when window/editor gains focus
    if (update.focusChanged && view.hasFocus) {
      this.showCursor(view, true)
      return
    }

    // Never hide cursor if only whitespace to the left
    if (onlyWhitespaceBefore) {
      this.showCursor(view)
      return
    }

    if (update.docChanged) {
      if (isDeleting) {
        // Backspace/delete - show cursor
        this.showCursor(view)
      } else {
        // Typing - hide cursor immediately, show after idle
        this.hideCursor(view)
        this.timeout = setTimeout(() => this.showCursor(view), 1500)
      }
    } else if (cursorMoved) {
      // Cursor moved without typing - show it instantly
      this.showCursor(view)
      if (hasSelection) {
        // But fade after 1s if there's a selection
        this.timeout = setTimeout(() => this.hideCursor(view), 1000)
      }
    } else if (hasSelection) {
      // Selection exists, fade after 1s
      this.timeout = setTimeout(() => this.hideCursor(view), 1000)
    }
  }

  showCursor(view: EditorView, instant = false) {
    if (instant) {
      view.dom.classList.add('cursor-no-transition')
      view.dom.classList.remove('cursor-hidden')
      // Remove the no-transition class after a frame so future transitions work
      requestAnimationFrame(() => view.dom.classList.remove('cursor-no-transition'))
    } else {
      view.dom.classList.remove('cursor-hidden')
    }
  }

  hideCursor(view: EditorView) {
    view.dom.classList.add('cursor-hidden')
  }

  destroy() {
    if (this.timeout) clearTimeout(this.timeout)
  }
})

const selectionHighlighter = ViewPlugin.fromClass(class {
  decorations: DecorationSet

  constructor(view: EditorView) {
    this.decorations = this.buildDecorations(view)
  }

  update(update: ViewUpdate) {
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
  onToggleTheme: () => void
  onSystemTheme: () => void
}

export function Editor(props: EditorProps) {
  let containerRef: HTMLDivElement | undefined
  let view: EditorView | undefined

  let aiAbortController: AbortController | null = null
  let pendingAiRequest: (() => void) | null = null
  const [showApiKeyDialog, setShowApiKeyDialog] = createSignal(false)

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
          props.onToggleTheme()
          return true
        },
      },
      {
        key: 'Mod-Shift-d',
        run: () => {
          props.onSystemTheme()
          return true
        },
      },
      {
        key: 'Mod-l',
        run: (view) => {
          const { head } = view.state.selection.main
          const line = view.state.doc.lineAt(head)
          view.dispatch({
            selection: { anchor: line.from, head: line.to },
          })
          return true
        },
      },
      {
        key: 'Tab',
        run: indentMore,
      },
      {
        key: 'Shift-Tab',
        run: indentLess,
      },
      {
        key: 'Mod-k',
        run: (view) => {
          // Don't start new request if one is in progress
          if (aiAbortController) return true

          const { from, to } = view.state.selection.main
          let selFrom = from, selTo = to

          // If no selection, use current line
          if (from === to) {
            const line = view.state.doc.lineAt(from)
            selFrom = line.from
            selTo = line.to
          }

          const selectedText = view.state.doc.sliceString(selFrom, selTo)
          if (!selectedText.trim()) return true

          // Get API key
          let apiKey = localStorage.getItem('openai-api-key')
          if (!apiKey) {
            // Store the request to run after key is entered
            pendingAiRequest = () => {
              // Re-trigger Cmd+K
              const event = new KeyboardEvent('keydown', { key: 'k', metaKey: true })
              view.contentDOM.dispatchEvent(event)
            }
            setShowApiKeyDialog(true)
            return true
          }

          // Select the range and show loading state
          view.dispatch({
            selection: { anchor: selFrom, head: selTo },
          })
          view.dom.classList.add('ai-loading')

          // Build context with selection marked
          const contextWithMarker =
            view.state.doc.sliceString(0, selFrom) +
            '<<<SELECTED>>>' + selectedText + '<<</SELECTED>>>' +
            view.state.doc.sliceString(selTo)

          // Create abort controller for cancellation
          aiAbortController = new AbortController()

          fetch('https://api.openai.com/v1/chat/completions', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${apiKey}`,
            },
            body: JSON.stringify({
              model: 'gpt-5.2',
              messages: [
                {
                  role: 'system',
                  content: 'You are a helpful writing assistant. The user will show you a document with a selected portion marked between <<<SELECTED>>> and <<</SELECTED>>>. Return ONLY a fixed-up version of the selected text. Fix typos, grammar, improve clarity. Replace placeholders with real content: "tk" or "TK" means "to come" and should be replaced with the correct information (e.g. "tk wrote Lord of the Flies" → "William Golding wrote Lord of the Flies"), TODO comments should be addressed, THINGS IN ALL CAPS are placeholders, and [text in square brackets] should be filled in or if it contains comma-separated options like [large, big, enormous] pick the best word for the context. Return ONLY the replacement text with no explanation or markdown formatting.',
                },
                {
                  role: 'user',
                  content: contextWithMarker,
                },
              ],
              max_completion_tokens: 1000,
            }),
            signal: aiAbortController.signal,
          })
            .then(res => res.json())
            .then(data => {
              view.dom.classList.remove('ai-loading')
              aiAbortController = null
              const replacement = data.choices?.[0]?.message?.content
              if (replacement) {
                view.dispatch({
                  changes: { from: selFrom, to: selTo, insert: replacement },
                  selection: { anchor: selFrom + replacement.length },
                })
              } else if (data.error) {
                console.error('OpenAI error:', data.error)
                alert('API error: ' + (data.error.message || 'Unknown error'))
              }
            })
            .catch(err => {
              view.dom.classList.remove('ai-loading')
              aiAbortController = null
              if (err.name !== 'AbortError') {
                console.error('AI fix error:', err)
                alert('Failed to connect to OpenAI')
              }
            })

          return true
        },
      },
      {
        key: 'Escape',
        run: (view) => {
          if (aiAbortController) {
            aiAbortController.abort()
            aiAbortController = null
            view.dom.classList.remove('ai-loading')
            // Collapse selection to end
            const { to } = view.state.selection.main
            view.dispatch({ selection: { anchor: to } })
            return true
          }
          return false
        },
      },
      {
        key: 'Mod-Shift-8',
        run: (view) => {
          const { from, to, head } = view.state.selection.main
          const startLine = view.state.doc.lineAt(from)
          const endLine = view.state.doc.lineAt(to)
          const cursorLine = view.state.doc.lineAt(head)
          const cursorOffset = head - cursorLine.from

          const changes: { from: number; to: number; insert: string }[] = []
          let adding = false

          for (let i = startLine.number; i <= endLine.number; i++) {
            const line = view.state.doc.line(i)
            const text = line.text

            if (text.startsWith('* ')) {
              // Remove bullet
              changes.push({ from: line.from, to: line.from + 2, insert: '' })
            } else {
              // Add bullet
              changes.push({ from: line.from, to: line.from, insert: '* ' })
              if (i === cursorLine.number) adding = true
            }
          }

          const newCursorPos = adding ? head + 2 : Math.max(cursorLine.from, head - 2)
          view.dispatch({ changes, selection: { anchor: newCursorPos } })
          return true
        },
      },
      {
        key: 'Mod-Shift-l',
        run: (view) => {
          const { from, to, head } = view.state.selection.main
          const startLine = view.state.doc.lineAt(from)
          const endLine = view.state.doc.lineAt(to)
          const cursorLine = view.state.doc.lineAt(head)

          const changes: { from: number; to: number; insert: string }[] = []
          let cursorDelta = 0

          for (let i = startLine.number; i <= endLine.number; i++) {
            const line = view.state.doc.line(i)
            const text = line.text

            if (text.match(/^- \[[x ]\] /)) {
              // Remove checkbox
              changes.push({ from: line.from, to: line.from + 6, insert: '' })
              if (i === cursorLine.number) cursorDelta = -6
            } else if (text.match(/^- \[[x ]\]/)) {
              // Remove checkbox (no trailing space)
              changes.push({ from: line.from, to: line.from + 5, insert: '' })
              if (i === cursorLine.number) cursorDelta = -5
            } else {
              // Add checkbox
              changes.push({ from: line.from, to: line.from, insert: '- [ ] ' })
              if (i === cursorLine.number) cursorDelta = 6
            }
          }

          const newCursorPos = Math.max(cursorLine.from, head + cursorDelta)
          view.dispatch({ changes, selection: { anchor: newCursorPos } })
          return true
        },
      },
      {
        key: 'Mod-Enter',
        run: (view) => {
          const { head } = view.state.selection.main
          const line = view.state.doc.lineAt(head)
          const text = line.text

          const unchecked = text.indexOf('- [ ]')
          const checked = text.indexOf('- [x]')

          if (unchecked !== -1) {
            // Check it
            view.dispatch({
              changes: { from: line.from + unchecked + 3, to: line.from + unchecked + 4, insert: 'x' },
            })
            return true
          } else if (checked !== -1) {
            // Uncheck it
            view.dispatch({
              changes: { from: line.from + checked + 3, to: line.from + checked + 4, insert: ' ' },
            })
            return true
          }

          return false
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
        firstLineHighlighter,
        checkboxHighlighter,
        headingHighlighter,
        blockquoteHighlighter,
        emphasisHighlighter,
        linkStyler,
        linkTruncator,
        EditorView.domEventHandlers({
          click: (event, view) => {
            const target = event.target as HTMLElement

            // Handle checkbox clicks
            if (target.classList.contains('checkbox-marker')) {
              event.preventDefault()
              const pos = view.posAtDOM(target)
              const line = view.state.doc.lineAt(pos)
              const text = line.text

              const unchecked = text.indexOf('- [ ]')
              const checked = text.indexOf('- [x]')

              if (unchecked !== -1) {
                view.dispatch({
                  changes: { from: line.from + unchecked + 3, to: line.from + unchecked + 4, insert: 'x' },
                })
              } else if (checked !== -1) {
                view.dispatch({
                  changes: { from: line.from + checked + 3, to: line.from + checked + 4, insert: ' ' },
                })
              }
              return true
            }

            // Handle link clicks (Cmd+click only)
            if (event.metaKey) {
              // Handle truncated URL widget clicks
              if (target.classList.contains('link-url-truncated')) {
                event.preventDefault()
                const url = target.getAttribute('data-full-url')
                if (url) {
                  open(url)
                }
                return true
              }

              // Handle link clicks by position
              const pos = view.posAtCoords({ x: event.clientX, y: event.clientY })
              if (pos !== null) {
                const line = view.state.doc.lineAt(pos)
                const text = line.text
                const offsetInLine = pos - line.from

                // Check for markdown link [text](url)
                const mdLinkRegex = /\[([^\]]+)\]\(([^)]+)\)/g
                let match
                while ((match = mdLinkRegex.exec(text)) !== null) {
                  const linkStart = match.index
                  const linkTextEnd = match.index + 1 + match[1].length // end of link text
                  if (offsetInLine >= linkStart + 1 && offsetInLine <= linkTextEnd) {
                    event.preventDefault()
                    let url = match[2]
                    // Add https:// if no protocol
                    if (!url.match(/^https?:\/\//)) {
                      url = 'https://' + url
                    }
                    open(url)
                    return true
                  }
                }

                // Check for bare URL
                const bareUrlRegex = /https?:\/\/[^\s\])<>]+/g
                while ((match = bareUrlRegex.exec(text)) !== null) {
                  // Skip if inside markdown link
                  const beforeMatch = text.slice(0, match.index)
                  if (beforeMatch.match(/\]\($/)) continue

                  if (offsetInLine >= match.index && offsetInLine <= match.index + match[0].length) {
                    event.preventDefault()
                    open(match[0])
                    return true
                  }
                }
              }
            }

            return false
          },
        }),
        cursorHider,
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

  const handleApiKeySubmit = (key: string) => {
    localStorage.setItem('openai-api-key', key)
    setShowApiKeyDialog(false)
    if (pendingAiRequest) {
      const request = pendingAiRequest
      pendingAiRequest = null
      // Small delay to let dialog close
      setTimeout(request, 50)
    }
  }

  const handleApiKeyCancel = () => {
    setShowApiKeyDialog(false)
    pendingAiRequest = null
  }

  return (
    <>
      <div ref={containerRef} class="editor-container" />
      <Show when={showApiKeyDialog()}>
        <ApiKeyDialog onSubmit={handleApiKeySubmit} onCancel={handleApiKeyCancel} />
      </Show>
    </>
  )
}
