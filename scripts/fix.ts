#!/usr/bin/env npx tsx
/**
 * Verified Fix Script
 *
 * Runs the fix workflow using Claude CLI, streaming output in real-time.
 * Can be run locally or in CI.
 *
 * Usage:
 *   npx tsx scripts/fix.ts "the bug description"
 *   npm run fix -- "the bug description"
 */

import { spawn } from 'child_process'
import * as readline from 'readline'

const WORKFLOW_PROMPT = `You are fixing a bug or implementing a feature in Drift, a minimalist note-taking app.

## The Issue
{ISSUE}

## Workflow

Follow these phases strictly. DO NOT SKIP ANY PHASE. Output your progress as you go.

### Phase 1: Understand
- Analyze the issue
- Search the codebase to understand relevant code
- Create a verification plan: what will you screenshot to prove it's broken? What will prove it's fixed?

### Phase 2: Capture "Before" State (REQUIRED)
- Write a Playwright test in e2e/ that captures the current state
- DO NOT manually start the dev server - Playwright handles this automatically via webServer config
- The test MUST take a screenshot showing the problem or current state
- Use assertScreenshot() with save option to persist the screenshot
- Run the test to capture the "before" evidence

Example test structure:
\`\`\`typescript
import { test, expect } from '@playwright/test'
import { getTauriMockScript } from './tauri-mocks'
import { assertScreenshot } from './helpers/screenshots'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('verify issue', async ({ page }) => {
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Setup state and capture screenshot
  const result = await assertScreenshot(page, 'description of what to verify', {
    save: { testFile: import.meta.url, name: 'before' }
  })
  console.log('Assertion:', result)
})
\`\`\`

Run tests with: npx playwright test <test-name> --project=chromium
Playwright will auto-start the dev server.

### Phase 3: Implement Fix
- Make the necessary code changes
- Run \`npx tsc --noEmit\` to catch type errors
- Keep changes minimal and focused

### Phase 4: Verify Fix (REQUIRED)
- Run the SAME test again
- It should now capture the "after" state showing the fix works
- Update the test to save an "after" screenshot
- The assertScreenshot() assertion should PASS confirming the fix

### Phase 5: Report Results
Output a final summary in this EXACT format (no variations):

---RESULT---
status: success|failure
before_screenshot: <actual file path, NOT "N/A">
after_screenshot: <actual file path, NOT "N/A">
files_changed:
  - <file1>
  - <file2>
summary: <one line description>
---END---

## CRITICAL RULES
1. NEVER skip the before/after screenshots - they are REQUIRED
2. NEVER report "N/A" for screenshots - always capture visual evidence
3. Even for "non-visual" changes, find a way to show proof (console output, dev tools, etc)
4. If you truly cannot capture evidence, report status: failure with explanation
5. Use e2e/helpers/screenshots.ts assertScreenshot() for all visual assertions
`

interface StreamMessage {
  type: string
  message?: {
    role?: string
    content?: Array<{ type: string; text?: string; name?: string; input?: unknown }>
  }
  content_block?: {
    type: string
    text?: string
    name?: string
  }
  delta?: {
    type: string
    text?: string
  }
  result?: {
    output?: string
  }
}

function formatToolUse(name: string, input: unknown): string {
  const inputStr = typeof input === 'string' ? input : JSON.stringify(input, null, 2)
  // Truncate long inputs
  const truncated = inputStr.length > 200 ? inputStr.slice(0, 200) + '...' : inputStr
  return `🔧 ${name}: ${truncated}`
}

async function main() {
  const issue = process.argv.slice(2).join(' ')

  if (!issue) {
    console.error('Usage: npx tsx scripts/fix.ts "issue description"')
    process.exit(1)
  }

  console.log('🔧 Starting verified fix workflow...')
  console.log(`📋 Issue: ${issue}`)
  console.log('─'.repeat(60))

  const prompt = WORKFLOW_PROMPT.replace('{ISSUE}', issue)

  // Run Claude CLI with streaming JSON output
  const claude = spawn('claude', [
    '--print',
    '--verbose',
    '--output-format', 'stream-json',
    '--max-turns', '50',
    '--dangerously-skip-permissions',
    prompt
  ], {
    cwd: process.cwd(),
    stdio: ['inherit', 'pipe', 'pipe'],
    env: { ...process.env }
  })

  let fullOutput = ''
  let currentText = ''

  const rl = readline.createInterface({
    input: claude.stdout!,
    crlfDelay: Infinity
  })

  rl.on('line', (line) => {
    if (!line.trim()) return

    try {
      const msg: StreamMessage = JSON.parse(line)

      // Handle different message types
      if (msg.type === 'assistant' && msg.message?.content) {
        for (const block of msg.message.content) {
          if (block.type === 'text' && block.text) {
            process.stdout.write(block.text)
            fullOutput += block.text
          } else if (block.type === 'tool_use' && block.name) {
            console.log(formatToolUse(block.name, block.input))
          }
        }
      } else if (msg.type === 'content_block_delta' && msg.delta?.text) {
        process.stdout.write(msg.delta.text)
        currentText += msg.delta.text
      } else if (msg.type === 'content_block_stop') {
        if (currentText) {
          fullOutput += currentText
          currentText = ''
        }
      } else if (msg.type === 'result' && msg.result?.output) {
        // Final result
        fullOutput += msg.result.output
        process.stdout.write(msg.result.output)
      }
    } catch {
      // Not JSON, just print it
      console.log(line)
    }
  })

  claude.stderr?.on('data', (data) => {
    process.stderr.write(data)
  })

  return new Promise<void>((resolve) => {
    claude.on('close', (code) => {
      console.log('\n' + '─'.repeat(60))

      // Parse the result
      const resultMatch = fullOutput.match(/---RESULT---([\s\S]*?)---END---/)
      if (resultMatch) {
        const resultBlock = resultMatch[1]
        const statusMatch = resultBlock.match(/status:\s*(success|failure)/)
        const status = statusMatch?.[1] || 'unknown'

        if (status === 'success') {
          console.log('✅ Fix verified successfully!')
          process.exit(0)
        } else {
          console.log('❌ Fix verification failed')
          process.exit(1)
        }
      } else {
        console.log('⚠️  Workflow did not complete (no result block found)')
        console.log('')
        console.log('This usually means Claude ran out of turns. Check:')
        console.log('  - e2e/screenshots/*/  for any captured screenshots')
        console.log('  - git diff            for any code changes made')
        console.log('')
        console.log('You may be able to resume or retry the task.')
        process.exit(code || 1)
      }

      resolve()
    })

    claude.on('error', (err) => {
      console.error('Failed to start Claude:', err)
      process.exit(1)
    })
  })
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
