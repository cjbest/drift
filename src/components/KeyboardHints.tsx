import { Show } from 'solid-js'
import './KeyboardHints.css'

interface KeyboardHintsProps {
  visible: boolean
}

interface Shortcut {
  keys: string
  description: string
}

const shortcuts: Shortcut[] = [
  { keys: '⌘N', description: 'New Note' },
  { keys: '⌘P', description: 'Open Note' },
  { keys: '⌘⇧N', description: 'New Window' },
  { keys: '⌘D', description: 'Toggle Theme' },
  { keys: '⌘F', description: 'Find' },
  { keys: '⌘K', description: 'AI Fix' },
]

export default function KeyboardHints(props: KeyboardHintsProps) {
  return (
    <Show when={props.visible}>
      <div class="keyboard-hints">
        {shortcuts.map((shortcut) => (
          <div class="keyboard-hint">
            <span class="hint-keys">{shortcut.keys}</span>
            <span class="hint-description">{shortcut.description}</span>
          </div>
        ))}
      </div>
    </Show>
  )
}
