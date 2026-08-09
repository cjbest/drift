import { createMemo } from 'solid-js'
import './DoomFace.css'

interface DoomFaceProps {
  content: string
}

// DOOM-style ASCII art faces that get progressively more damaged
const FACES = {
  healthy: `
   _______
  /       \\
 |  ^   ^  |
 |    >    |
 |  \\___/  |
  \\_______/
  `,
  scratched: `
   _______
  /   _   \\
 | \\ ^   ^ |
 |    >    |
 |  \\___/  |
  \\_______/
  `,
  bruised: `
   _______
  /  ___  \\
 | X  ^   |
 |    <    |
 |  \\___/  |
  \\_______/
  `,
  bloodied: `
   _______
  / -___  \\
 | X   X  |
 |    o    |
 |  \\___/  |
  \\_______/
  `,
  beaten: `
   _______
  /_-_-_  \\
 | X   X  |
 |    ~    |
 |   ___   |
  \\_______/
  `,
  dead: `
   _______
  /_______\\
 | X   X  |
 |    o    |
 |  _____  |
  \\_______/
  `,
  skull1: `
   _______
  / _ _ _ \\
 | X   X  |
 |    Λ    |
 |  =====  |
  \\_______/
  `,
  skull2: `
   _______
  /_______\\
 | X   X  |
 |    V    |
 | ======= |
  \\_______/
  `,
  skull3: `
   _______
  /=======\\
 | X   X  |
 |   < >   |
 |=========|
  \\_______/
  `,
  exploded: `
   *  _  *
  /* - - *\\
 |*X * X *|
 | * V *  |
 |*=====* |
  \\*_____*/
  `
}

export function DoomFace(props: DoomFaceProps) {
  // Count words in the content
  const wordCount = createMemo(() => {
    const text = props.content.trim()
    if (!text) return 0
    return text.split(/\s+/).length
  })

  // Determine which face to show based on word count
  const currentFace = createMemo(() => {
    const count = wordCount()

    if (count < 100) return FACES.healthy
    if (count < 200) return FACES.scratched
    if (count < 300) return FACES.bruised
    if (count < 400) return FACES.bloodied
    if (count < 500) return FACES.beaten
    if (count < 600) return FACES.dead
    if (count < 700) return FACES.skull1
    if (count < 800) return FACES.skull2
    if (count < 900) return FACES.skull3
    return FACES.exploded
  })

  // Get the status text
  const statusText = createMemo(() => {
    const count = wordCount()

    if (count < 100) return 'Fresh'
    if (count < 200) return 'Scratched'
    if (count < 300) return 'Bruised'
    if (count < 400) return 'Bloodied'
    if (count < 500) return 'Beaten'
    if (count < 600) return 'Dead'
    if (count < 800) return 'Skull'
    if (count < 900) return 'Bones'
    return 'EXPLODED!'
  })

  // Get color class based on health
  const colorClass = createMemo(() => {
    const count = wordCount()

    if (count < 200) return 'healthy'
    if (count < 400) return 'warning'
    if (count < 600) return 'danger'
    return 'dead'
  })

  return (
    <div class="doom-face-container">
      <pre class={`doom-face ${colorClass()}`}>{currentFace()}</pre>
      <div class="doom-status">
        <div class={`doom-status-text ${colorClass()}`}>{statusText()}</div>
        <div class="doom-word-count">{wordCount()} words</div>
      </div>
    </div>
  )
}
