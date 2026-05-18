// Uploads the long-note scroll test video to Gemini and asks for a verdict.
// Usage: node scripts/verify-scroll-with-gemini.mjs <path-to-video.webm>
import fs from 'node:fs'
import path from 'node:path'

const apiKey = process.env.GEMINI_API_KEY
if (!apiKey) {
  console.error('GEMINI_API_KEY not set')
  process.exit(2)
}

const videoPath = process.argv[2]
const promptFile = process.argv[3]
if (!videoPath) {
  console.error('Usage: node scripts/verify-scroll-with-gemini.mjs <video.webm> [prompt-file.txt]')
  process.exit(2)
}

const absPath = path.resolve(videoPath)
const bytes = fs.readFileSync(absPath)
const sizeMb = bytes.length / (1024 * 1024)
console.error(`Video: ${absPath}  size: ${sizeMb.toFixed(2)} MB`)

if (bytes.length > 19 * 1024 * 1024) {
  console.error('Video too large for inline upload; use the File API instead.')
  process.exit(2)
}

const defaultPrompt = `You are reviewing an end-to-end test recording of a desktop note-taking app called Drift.
The test seeds the editor with a 100-line note: a title line followed by 99 lines reading
"Line 001 — quick brown fox jumps over the lazy dog" through "Line 099 — quick brown fox jumps over the lazy dog".

The test then exercises viewport scrolling:
  1. Press PageDown ~12 times (should scroll the viewport down through the note).
  2. Press PageUp ~12 times (should scroll back to the top).
  3. Mouse-wheel scroll down ~8 times.

Watch the video carefully and answer with a single JSON object of the form:
  {"passed": true|false, "confidence": 0-1, "explanation": "..."}

The assertion you are verifying is: "Viewport scrolling for long notes works correctly — the
visible content changes as the user scrolls down (later 'Line NNN' rows come into view) and
returns to earlier rows when the user scrolls back up. The editor does not appear frozen,
clipped, or stuck on the same lines."

Reply with ONLY the JSON object — no markdown, no preamble.`

const prompt = promptFile ? fs.readFileSync(promptFile, 'utf8') : defaultPrompt

const body = {
  contents: [
    {
      parts: [
        {
          inline_data: {
            mime_type: 'video/webm',
            data: bytes.toString('base64'),
          },
        },
        { text: prompt },
      ],
    },
  ],
  generationConfig: {
    temperature: 0,
    maxOutputTokens: 4096,
    thinkingConfig: { thinkingBudget: 1024 },
  },
}

const model = process.env.GEMINI_MODEL || 'gemini-2.5-pro'
const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`

const res = await fetch(url, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(body),
})

if (!res.ok) {
  console.error(`HTTP ${res.status}`)
  console.error(await res.text())
  process.exit(3)
}

const data = await res.json()
const text = data?.candidates?.[0]?.content?.parts?.map(p => p.text).filter(Boolean).join('') ?? ''

const jsonMatch = text.match(/\{[\s\S]*\}/)
if (!jsonMatch) {
  // Gemini truncates silently when it runs out of output tokens — surface the raw response.
  console.error('No JSON object in model output. finishReason:', data?.candidates?.[0]?.finishReason)
  console.error('Raw text:', text)
  process.exit(4)
}

const verdict = JSON.parse(jsonMatch[0])
console.log(JSON.stringify(verdict, null, 2))
process.exit(verdict.passed ? 0 : 1)
