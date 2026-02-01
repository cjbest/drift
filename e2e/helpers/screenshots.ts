import { Page } from '@playwright/test'
import * as path from 'path'
import { fileURLToPath } from 'url'
import Anthropic from '@anthropic-ai/sdk'
import * as dotenv from 'dotenv'

// Load .env from project root
const __dirname = path.dirname(fileURLToPath(import.meta.url))
dotenv.config({ path: path.join(__dirname, '../../.env') })

const SYSTEM_PROMPT = `You are a visual assertion engine for automated testing of a desktop application called "Drift".

## About Drift
Drift is a minimalist note-taking app built with Electron and CodeMirror. It features:
- A clean, distraction-free text editor
- Markdown support with a styled first-line title
- Light and dark themes
- Quick-open dialog for switching between notes (Cmd+P)
- System fonts (SF Pro / -apple-system on Mac)

## Your Role
You verify visual assertions during end-to-end testing. Engineers use you to confirm that:
1. Bug fixes actually work (comparing before/after states)
2. Features are correctly implemented
3. UI elements appear as expected

## Critical Instructions
**Accuracy is paramount.** Your assertions are used to automatically verify code changes. False positives (saying something is true when it isn't) will cause broken code to be merged. False negatives (saying something is false when it's true) will cause valid fixes to be rejected.

Be STRICT and LITERAL in your interpretations:
- If asked about a specific font, look carefully at letterforms (Comic Sans has distinctive rounded 'a', 'e', 'o')
- If asked about specific text, it must literally appear in the screenshot
- If asked about colors, examine the actual pixel colors, not assumptions
- If asked about UI elements, they must be clearly visible

When uncertain, err on the side of saying FALSE rather than guessing TRUE.

## Response Format
Respond with ONLY a JSON object, no markdown formatting, no explanation outside the JSON:
{"passed": boolean, "confidence": number, "explanation": "brief reason"}`

/**
 * Takes a screenshot with a standardized path based on test file and description.
 */
export async function screenshot(page: Page, testFile: string, description: string): Promise<string> {
  const testFileName = path.basename(testFile).replace(/\.spec\.(ts|js)$/, '').replace(/\.test\.(ts|js)$/, '')
  const safeDescription = description
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')

  const screenshotPath = path.join('e2e', 'screenshots', testFileName, `${safeDescription}.png`)
  await page.screenshot({ path: screenshotPath })
  return screenshotPath
}

export interface AssertScreenshotResult {
  passed: boolean
  confidence: number
  explanation: string
  screenshotPath?: string
}

export interface AssertScreenshotOptions {
  /** If provided, saves the screenshot to e2e/screenshots/<test>/<name>.png */
  save?: {
    testFile: string
    name: string
  }
  /** Model to use (default: claude-sonnet-4-5-20250929) */
  model?: 'claude-sonnet-4-5-20250929' | 'claude-opus-4-5-20251101'
}

/**
 * Asserts a visual condition by having Claude analyze the screenshot.
 */
export async function assertScreenshot(
  page: Page,
  assertion: string,
  options: AssertScreenshotOptions = {}
): Promise<AssertScreenshotResult> {
  const { save, model = 'claude-sonnet-4-5-20250929' } = options

  const apiKey = process.env.ANTHROPIC_API_KEY
  if (!apiKey) {
    throw new Error('ANTHROPIC_API_KEY not found in environment. Add it to .env file.')
  }

  const client = new Anthropic({ apiKey })

  // Take screenshot as buffer
  const screenshotBuffer = await page.screenshot()
  const base64Image = screenshotBuffer.toString('base64')

  // Also save to permanent location if requested
  let screenshotPath: string | undefined
  if (save) {
    screenshotPath = await screenshot(page, save.testFile, save.name)
  }

  const response = await client.messages.create({
    model,
    max_tokens: 256,
    system: SYSTEM_PROMPT,
    messages: [
      {
        role: 'user',
        content: [
          {
            type: 'image',
            source: {
              type: 'base64',
              media_type: 'image/png',
              data: base64Image,
            },
          },
          {
            type: 'text',
            text: `Verify this assertion: "${assertion}"`,
          },
        ],
      },
    ],
  })

  // Extract text from response
  const textContent = response.content.find(block => block.type === 'text')
  if (!textContent || textContent.type !== 'text') {
    throw new Error('No text response from Claude')
  }

  // Parse JSON from response
  const jsonMatch = textContent.text.match(/\{[\s\S]*\}/)
  if (!jsonMatch) {
    throw new Error(`Could not find JSON in response: ${textContent.text}`)
  }

  const parsed = JSON.parse(jsonMatch[0])
  return {
    passed: parsed.passed,
    confidence: parsed.confidence,
    explanation: parsed.explanation,
    screenshotPath,
  }
}

/**
 * Compares before/after screenshots to verify a fix.
 */
export async function assertBeforeAfter(
  beforePath: string,
  afterPath: string,
  assertion: string,
  options: { model?: 'claude-sonnet-4-5-20250929' | 'claude-opus-4-5-20251101' } = {}
): Promise<AssertScreenshotResult> {
  const { model = 'claude-sonnet-4-5-20250929' } = options

  const apiKey = process.env.ANTHROPIC_API_KEY
  if (!apiKey) {
    throw new Error('ANTHROPIC_API_KEY not found in environment')
  }

  const client = new Anthropic({ apiKey })

  const beforeBuffer = await import('fs').then(fs => fs.promises.readFile(beforePath))
  const afterBuffer = await import('fs').then(fs => fs.promises.readFile(afterPath))

  const response = await client.messages.create({
    model,
    max_tokens: 256,
    system: SYSTEM_PROMPT,
    messages: [
      {
        role: 'user',
        content: [
          {
            type: 'text',
            text: 'BEFORE screenshot:',
          },
          {
            type: 'image',
            source: {
              type: 'base64',
              media_type: 'image/png',
              data: beforeBuffer.toString('base64'),
            },
          },
          {
            type: 'text',
            text: 'AFTER screenshot:',
          },
          {
            type: 'image',
            source: {
              type: 'base64',
              media_type: 'image/png',
              data: afterBuffer.toString('base64'),
            },
          },
          {
            type: 'text',
            text: `Verify this assertion about what changed: "${assertion}"`,
          },
        ],
      },
    ],
  })

  const textContent = response.content.find(block => block.type === 'text')
  if (!textContent || textContent.type !== 'text') {
    throw new Error('No text response from Claude')
  }

  const jsonMatch = textContent.text.match(/\{[\s\S]*\}/)
  if (!jsonMatch) {
    throw new Error(`Could not find JSON in response: ${textContent.text}`)
  }

  const parsed = JSON.parse(jsonMatch[0])
  return {
    passed: parsed.passed,
    confidence: parsed.confidence,
    explanation: parsed.explanation,
  }
}
