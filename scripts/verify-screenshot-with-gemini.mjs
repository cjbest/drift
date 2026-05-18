// Uploads a single screenshot to Gemini and asks for a JSON verdict.
// Usage: node scripts/verify-screenshot-with-gemini.mjs <image.png> <prompt-file.txt>
import fs from 'node:fs'
import path from 'node:path'

const apiKey = process.env.GEMINI_API_KEY
if (!apiKey) {
  console.error('GEMINI_API_KEY not set')
  process.exit(2)
}

const imagePath = process.argv[2]
const promptFile = process.argv[3]
if (!imagePath || !promptFile) {
  console.error('Usage: node scripts/verify-screenshot-with-gemini.mjs <image.png> <prompt-file.txt>')
  process.exit(2)
}

const bytes = fs.readFileSync(path.resolve(imagePath))
const prompt = fs.readFileSync(path.resolve(promptFile), 'utf8')

const body = {
  contents: [
    {
      parts: [
        {
          inline_data: {
            mime_type: 'image/png',
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
  console.error('No JSON object in model output. finishReason:', data?.candidates?.[0]?.finishReason)
  console.error('Raw text:', text)
  process.exit(4)
}

const verdict = JSON.parse(jsonMatch[0])
console.log(JSON.stringify(verdict, null, 2))
process.exit(verdict.passed ? 0 : 1)
