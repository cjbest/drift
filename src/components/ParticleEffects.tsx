import { createSignal, onCleanup, For } from 'solid-js'
import './ParticleEffects.css'

interface Particle {
  id: number
  x: number
  y: number
  vx: number
  vy: number
  life: number
  maxLife: number
  color: string
  size: number
}

let particleId = 0

export function ParticleEffects() {
  const [particles, setParticles] = createSignal<Particle[]>([])
  let animationFrame: number | null = null

  // Animation loop
  const animate = () => {
    setParticles(prev => {
      return prev
        .map(p => ({
          ...p,
          x: p.x + p.vx,
          y: p.y + p.vy,
          vy: p.vy + 0.15, // gravity
          life: p.life - 1
        }))
        .filter(p => p.life > 0)
    })
    animationFrame = requestAnimationFrame(animate)
  }

  animate()

  onCleanup(() => {
    if (animationFrame) {
      cancelAnimationFrame(animationFrame)
    }
  })

  // Expose method to create particles
  ;(window as any).__emitParticles = (x: number, y: number) => {
    const colors = ['#ff6b6b', '#4ecdc4', '#45b7d1', '#96ceb4', '#ffeaa7', '#dfe6e9', '#a29bfe']
    const newParticles: Particle[] = []

    // Create 3-5 particles per keypress
    const count = Math.floor(Math.random() * 3) + 3

    for (let i = 0; i < count; i++) {
      newParticles.push({
        id: particleId++,
        x,
        y,
        vx: (Math.random() - 0.5) * 3,
        vy: -Math.random() * 3 - 1,
        life: 60,
        maxLife: 60,
        color: colors[Math.floor(Math.random() * colors.length)],
        size: Math.random() * 4 + 2
      })
    }

    setParticles(prev => [...prev, ...newParticles])
  }

  return (
    <div class="particle-container">
      <For each={particles()}>
        {(particle) => {
          const opacity = particle.life / particle.maxLife
          return (
            <div
              class="particle"
              style={{
                left: `${particle.x}px`,
                top: `${particle.y}px`,
                width: `${particle.size}px`,
                height: `${particle.size}px`,
                'background-color': particle.color,
                opacity: opacity.toString()
              }}
            />
          )
        }}
      </For>
    </div>
  )
}
