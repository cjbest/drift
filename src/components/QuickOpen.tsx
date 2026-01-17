import { createSignal, createEffect, onMount, onCleanup, For } from 'solid-js'
import './QuickOpen.css'

interface QuickOpenProps {
  recentFiles: string[]
  onSelect: (filePath: string) => void
  onClose: () => void
  listAllNotes: () => Promise<string[]>
}

function getFilename(path: string): string {
  return path.split('/').pop()?.replace('.md', '') || path
}

function fuzzyMatch(query: string, text: string): boolean {
  const lowerQuery = query.toLowerCase()
  const lowerText = text.toLowerCase()
  let qi = 0
  for (let ti = 0; ti < lowerText.length && qi < lowerQuery.length; ti++) {
    if (lowerText[ti] === lowerQuery[qi]) qi++
  }
  return qi === lowerQuery.length
}

export function QuickOpen(props: QuickOpenProps) {
  const [query, setQuery] = createSignal('')
  const [allFiles, setAllFiles] = createSignal<string[]>([])
  const [filteredFiles, setFilteredFiles] = createSignal<string[]>([])
  const [selectedIndex, setSelectedIndex] = createSignal(0)

  let inputRef: HTMLInputElement | undefined

  onMount(async () => {
    // Load all notes
    const notes = await props.listAllNotes()
    setAllFiles(notes)

    // Start with recent files if no query
    updateFilteredFiles('')

    // Focus input
    inputRef?.focus()
  })

  const updateFilteredFiles = (q: string) => {
    if (!q.trim()) {
      // Show recent files first, then others
      const recent = props.recentFiles.filter(f => allFiles().includes(f))
      const others = allFiles().filter(f => !props.recentFiles.includes(f))
      setFilteredFiles([...recent, ...others])
    } else {
      // Filter by query
      const matches = allFiles().filter(f => fuzzyMatch(q, getFilename(f)))
      setFilteredFiles(matches)
    }
    setSelectedIndex(0)
  }

  createEffect(() => {
    updateFilteredFiles(query())
  })

  const handleKeyDown = (e: KeyboardEvent) => {
    // Stop all keyboard events from reaching CodeMirror
    e.stopPropagation()

    const files = filteredFiles()

    switch (e.key) {
      case 'ArrowDown':
        e.preventDefault()
        setSelectedIndex(i => Math.min(i + 1, files.length - 1))
        break
      case 'ArrowUp':
        e.preventDefault()
        setSelectedIndex(i => Math.max(i - 1, 0))
        break
      case 'Enter':
        e.preventDefault()
        if (files[selectedIndex()]) {
          props.onSelect(files[selectedIndex()])
        }
        break
      case 'Escape':
        e.preventDefault()
        props.onClose()
        break
    }
  }

  return (
    <div class="quick-open-overlay" onClick={() => props.onClose()}>
      <div class="quick-open" onClick={e => e.stopPropagation()}>
        <input
          ref={inputRef}
          type="text"
          class="quick-open-input"
          placeholder="Search notes..."
          value={query()}
          onInput={e => setQuery(e.currentTarget.value)}
          onKeyDown={handleKeyDown}
        />
        <div class="quick-open-list">
          <For each={filteredFiles()}>
            {(file, index) => (
              <div
                class="quick-open-item"
                classList={{ selected: index() === selectedIndex() }}
                onClick={() => props.onSelect(file)}
              >
                {getFilename(file)}
              </div>
            )}
          </For>
          {filteredFiles().length === 0 && (
            <div class="quick-open-empty">No notes found</div>
          )}
        </div>
      </div>
    </div>
  )
}
