import { Page } from '@playwright/test'
import * as path from 'path'
import * as fs from 'fs'
import { execSync, spawnSync } from 'child_process'

/**
 * Takes a screenshot with a standardized path based on test file and description.
 * Screenshots are committed to provide visual history of test states.
 *
 * Directory structure mirrors test structure:
 *   e2e/screenshots/<test-name>/<description>.png
 *
 * @param page - Playwright page
 * @param testFile - The test file path (use import.meta.url or __filename)
 * @param description - Short description of what the screenshot shows (kebab-case)
 *
 * @example
 * await screenshot(page, import.meta.url, 'bullet-indent-correct')
 * // Saves to: e2e/screenshots/my-test/bullet-indent-correct.png
 */
export async function screenshot(page: Page, testFile: string, description: string): Promise<string> {
  // Extract test name from file path (e.g., "my-feature.spec.ts" -> "my-feature")
  const testFileName = path.basename(testFile).replace(/\.spec\.(ts|js)$/, '').replace(/\.test\.(ts|js)$/, '')

  // Ensure description is kebab-case and safe for filenames
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
  /** Model to use (default: sonnet) */
  model?: string
}

/**
 * Asserts a visual condition by having Claude analyze the screenshot.
 * Uses the Claude CLI, so no API key needed - just uses your existing Claude Code auth.
 *
 * @param page - Playwright page
 * @param assertion - What to verify (e.g., "all wrapped lines are indented consistently")
 * @param options - Optional: save screenshot, adjust model
 *
 * @example
 * // Quick assertion (no save)
 * const result = await assertScreenshot(page, 'the button is visible and enabled')
 * expect(result.passed).toBe(true)
 *
 * @example
 * // Important assertion (save for visual history)
 * await assertScreenshot(page, 'bullet indentation is correct on all wrapped lines', {
 *   save: { testFile: import.meta.url, name: 'bullet-indent-correct' }
 * })
 */
export async function assertScreenshot(
  page: Page,
  assertion: string,
  options: AssertScreenshotOptions = {}
): Promise<AssertScreenshotResult> {
  const { save, model = 'sonnet' } = options

  // Take screenshot as buffer
  const screenshotBuffer = await page.screenshot()

  // Also save to permanent location if requested
  let screenshotPath: string | undefined
  if (save) {
    screenshotPath = await screenshot(page, save.testFile, save.name)
  }

  // Ask Claude CLI to verify the assertion (pipe image via stdin)
  const prompt = `Look at this screenshot and verify this assertion: "${assertion}"

Respond with JSON only, no markdown, no other text:
{"passed": true/false, "confidence": 0.0-1.0, "explanation": "brief explanation"}`

  const result = spawnSync('claude', ['-p', '--model', model, prompt], {
    input: screenshotBuffer,
    encoding: 'utf-8',
    timeout: 60000
  })

  if (result.error) {
    throw result.error
  }

  if (result.status !== 0) {
    throw new Error(`Claude CLI failed: ${result.stderr}`)
  }

  // Parse JSON from response (might have extra text around it)
  const jsonMatch = result.stdout.match(/\{[\s\S]*\}/)
  if (!jsonMatch) {
    throw new Error(`Could not find JSON in response: ${result.stdout}`)
  }

  const parsed = JSON.parse(jsonMatch[0])
  return {
    passed: parsed.passed,
    confidence: parsed.confidence,
    explanation: parsed.explanation,
    screenshotPath
  }
}

/**
 * Compares before/after screenshots to verify a fix.
 * More robust than just checking "after" - confirms the change is visible.
 *
 * @param beforePath - Path to before screenshot
 * @param afterPath - Path to after screenshot
 * @param assertion - What changed (e.g., "the indent bug is now fixed")
 */
export async function assertBeforeAfter(
  beforePath: string,
  afterPath: string,
  assertion: string,
  options: { model?: string } = {}
): Promise<AssertScreenshotResult> {
  const { model = 'sonnet' } = options

  const prompt = `I'm showing you two screenshots. The first is BEFORE, the second is AFTER.

Verify this assertion about what changed: "${assertion}"

Respond with JSON only, no markdown, no other text:
{"passed": true/false, "confidence": 0.0-1.0, "explanation": "brief explanation of what changed"}`

  const result = execSync(
    `claude -p --model ${model} "${prompt.replace(/"/g, '\\"')}" "${beforePath}" "${afterPath}"`,
    { encoding: 'utf-8', timeout: 60000 }
  )

  const jsonMatch = result.match(/\{[\s\S]*\}/)
  if (!jsonMatch) {
    throw new Error(`Could not find JSON in response: ${result}`)
  }

  const parsed = JSON.parse(jsonMatch[0])
  return {
    passed: parsed.passed,
    confidence: parsed.confidence,
    explanation: parsed.explanation
  }
}
