#!/usr/bin/env npx tsx
/**
 * Verified Fix Script
 *
 * Runs the fix workflow using Claude CLI, streaming output in real-time.
 * Can be run locally or in CI.
 *
 * Usage:
 *   npm run fix -- --issue 123 "description"     # New fix from issue
 *   npm run fix -- --pr 8 "adjustment request"   # Adjust existing PR
 *   npm run fix -- "description"                 # Local adhoc testing
 */

import { spawn, execSync } from 'child_process'
import * as readline from 'readline'
import * as fs from 'fs'
import * as path from 'path'
// @ts-ignore - no types for this package
import ffmpegInstaller from '@ffmpeg-installer/ffmpeg'

const FFMPEG_PATH = ffmpegInstaller.path

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
All test files and screenshots go in: e2e/issues/{ISSUE_ID}/

- Create directory: e2e/issues/{ISSUE_ID}/
- Write test: e2e/issues/{ISSUE_ID}/verify.spec.ts
- Screenshots save to: e2e/issues/{ISSUE_ID}/screenshots/
- DO NOT manually start the dev server - Playwright handles this automatically
- The test MUST take a screenshot showing the problem or current state
- Use assertScreenshot() with save option to persist the screenshot
- Run the test to capture the "before" evidence

Example test structure (e2e/issues/{ISSUE_ID}/verify.spec.ts):
\`\`\`typescript
import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'
import { assertScreenshot } from '../../helpers/screenshots'

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

Run tests with: npx playwright test e2e/issues/{ISSUE_ID}/ --project=chromium

### Phase 3: Implement Fix
- Make the necessary code changes
- Run \`npx tsc --noEmit\` to catch type errors
- Keep changes minimal and focused

### Phase 4: Verify Fix (REQUIRED)
- Run the SAME test again
- It should now capture the "after" state showing the fix works
- Update the test to save an "after" screenshot
- The assertScreenshot() assertion should PASS confirming the fix

### Phase 5: Create Demo
Create a compelling demo that shows off the fix:
1. Write a demo test in e2e/issues/{ISSUE_ID}/demo.spec.ts that:
   - Uses test.slow() for pacing
   - Shows the feature/fix in action with realistic usage
   - Types with { delay: 40 } for human-like speed
   - Uses waitForTimeout() between actions for visual clarity
2. Run it: npx playwright test demo-fix --project=chromium
3. Playwright will record a video automatically

Example demo test:
\`\`\`typescript
test('demo: feature in action', async ({ page }) => {
  test.slow()
  // Use a compact viewport - no sidebar, just the editor
  await page.setViewportSize({ width: 600, height: 450 })
  await page.goto('/')
  // ... show the feature working with realistic interactions
})
\`\`\`

### Phase 6: Report Results
Output the PR content in this EXACT format:

---PR---
title: <short PR title, under 70 chars>
status: success|failure
issue_id: {ISSUE_ID}
demo_video: <path to the .webm video file in test-results/>

## Demo
<leave this line exactly as-is, the video will be converted to GIF and inserted here>

## Summary
<2-3 sentences explaining what was fixed and how>

## Before & After
| Before | After |
|--------|-------|
| ![before](e2e/issues/{ISSUE_ID}/screenshots/before.png) | ![after](e2e/issues/{ISSUE_ID}/screenshots/after.png) |
| <caption> | <caption> |

## Files Changed
- <file1>: <what changed>
- <file2>: <what changed>

## Tests
- \`e2e/issues/{ISSUE_ID}/verify.spec.ts\` - Verification test with before/after assertions
- \`e2e/issues/{ISSUE_ID}/demo.spec.ts\` - Demo recording
---END---

## CRITICAL RULES
1. NEVER skip the before/after screenshots - they are REQUIRED
2. NEVER report "N/A" for screenshots - always capture visual evidence
3. Even for "non-visual" changes, find a way to show proof (console output, dev tools, etc)
4. If you truly cannot capture evidence, report status: failure with explanation
5. Use e2e/helpers/screenshots.ts assertScreenshot() for all visual assertions

## IMPORTANT: Visual Assertion Integrity
The assertScreenshot() system is critical infrastructure we are actively developing.
If you encounter a case where:
- The assertion returns a result that seems CLEARLY WRONG (e.g., says "not blue" when text is obviously blue)
- You are tempted to bypass or work around the assertion

DO NOT work around it. Instead:
1. STOP the workflow immediately
2. Report status: failure
3. Include a detailed "assertion_bug" section in your output:

---ASSERTION_BUG---
screenshot_path: <path to the screenshot that was checked>
assertion: <the exact assertion text you used>
result: <what assertScreenshot returned>
expected: <what you believe the correct result should be>
explanation: <why you believe the assertion is wrong>
---END_BUG---

This helps us fix the visual assertion system. Never silently work around it.
`

const ADJUST_PROMPT = `You are adjusting an existing fix for Drift, a minimalist note-taking app.

## Original Issue
{ORIGINAL_ISSUE}

## What Was Implemented
{PR_SUMMARY}

## Conversation
{COMMENTS}

## Adjustment Request
{ADJUSTMENT}

## Current State
- Issue directory: e2e/issues/{ISSUE_ID}/
- Existing tests: verify.spec.ts, demo.spec.ts
- Screenshots in: e2e/issues/{ISSUE_ID}/screenshots/
- IMPORTANT: before.png shows the ORIGINAL state before any fix - DO NOT overwrite it!

## Workflow

1. **Understand the adjustment** - What needs to change?
2. **Update the implementation** - Modify the code as requested
3. **Run type check** - \`npx tsc --noEmit\`
4. **Update verification test** - Modify to only capture "after" screenshot (keep original "before")
5. **Capture new "after" screenshot** - Run the test, this updates after.png only
6. **Update demo** - Re-record e2e/issues/{ISSUE_ID}/demo.spec.ts if the change is visible
7. **Report results** - Output the updated PR content

CRITICAL: The "before" screenshot must ALWAYS show the original state before ANY fix was applied.
Never overwrite before.png during adjustments - only update after.png.

### Report Format
Output in this EXACT format:

---PR---
title: <same or updated title>
status: success|failure
issue_id: {ISSUE_ID}
demo_video: <path to .webm if re-recorded>

## Demo
<leave this line for GIF>

## Summary
<updated summary reflecting the adjustment>

## Before & After
| Before | After |
|--------|-------|
| ![before](e2e/issues/{ISSUE_ID}/screenshots/before.png) | ![after](e2e/issues/{ISSUE_ID}/screenshots/after.png) |
| <caption> | <caption> |

## Files Changed
- <file1>: <what changed>

## Adjustment Made
<describe what was adjusted based on feedback>
---END---
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

async function generatePreview(title: string, body: string, status: string): Promise<void> {
  // Convert relative image paths to absolute file:// URLs
  const bodyWithAbsolutePaths = body.replace(
    /!\[([^\]]*)\]\(([^)]+)\)/g,
    (match, alt, src) => {
      if (src.startsWith('http') || src.startsWith('file://')) return match
      const absPath = path.resolve(process.cwd(), src)
      return `![${alt}](file://${absPath})`
    }
  )

  const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>PR Preview: ${title}</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
      max-width: 900px;
      margin: 40px auto;
      padding: 20px;
      background: #f6f8fa;
    }
    .pr-container {
      background: white;
      border: 1px solid #d0d7de;
      border-radius: 6px;
      overflow: hidden;
    }
    .pr-header {
      padding: 16px;
      border-bottom: 1px solid #d0d7de;
      background: ${status === 'success' ? '#dafbe1' : '#ffebe9'};
    }
    .pr-title {
      font-size: 20px;
      font-weight: 600;
      margin: 0;
    }
    .pr-status {
      display: inline-block;
      padding: 4px 12px;
      border-radius: 20px;
      font-size: 12px;
      font-weight: 600;
      margin-top: 8px;
      background: ${status === 'success' ? '#1a7f37' : '#cf222e'};
      color: white;
    }
    .pr-body {
      padding: 16px;
    }
    .pr-body h2 {
      font-size: 16px;
      border-bottom: 1px solid #d0d7de;
      padding-bottom: 8px;
      margin-top: 24px;
    }
    .pr-body h2:first-child {
      margin-top: 0;
    }
    .pr-body img {
      max-width: 100%;
      border: 1px solid #d0d7de;
      border-radius: 6px;
      margin: 8px 0;
    }
    .pr-body ul, .pr-body ol {
      padding-left: 24px;
    }
    .pr-body code {
      background: #f6f8fa;
      padding: 2px 6px;
      border-radius: 3px;
      font-size: 85%;
    }
    .pr-body pre {
      background: #f6f8fa;
      padding: 16px;
      border-radius: 6px;
      overflow-x: auto;
    }
  </style>
</head>
<body>
  <div class="pr-container">
    <div class="pr-header">
      <h1 class="pr-title">${title}</h1>
      <span class="pr-status">${status === 'success' ? '✓ Ready to merge' : '✗ Needs work'}</span>
    </div>
    <div class="pr-body">
      ${markdownToHtml(bodyWithAbsolutePaths)}
    </div>
  </div>
</body>
</html>`

  const previewPath = path.join(process.cwd(), 'pr-preview.html')
  fs.writeFileSync(previewPath, html)
  execSync(`open "${previewPath}"`)
}

function markdownToHtml(md: string): string {
  return md
    // Headers
    .replace(/^### (.+)$/gm, '<h3>$1</h3>')
    .replace(/^## (.+)$/gm, '<h2>$1</h2>')
    .replace(/^# (.+)$/gm, '<h1>$1</h1>')
    // Images
    .replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img alt="$1" src="$2">')
    // Bold
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    // Italic
    .replace(/\*([^*]+)\*/g, '<em>$1</em>')
    // Code blocks
    .replace(/```(\w*)\n([\s\S]*?)```/g, '<pre><code>$2</code></pre>')
    // Inline code
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    // Unordered lists
    .replace(/^- (.+)$/gm, '<li>$1</li>')
    .replace(/(<li>.*<\/li>\n?)+/g, '<ul>$&</ul>')
    // Paragraphs (lines not already wrapped)
    .replace(/^(?!<[hluop]|$)(.+)$/gm, '<p>$1</p>')
    // Clean up
    .replace(/<\/ul>\n<ul>/g, '')
}

function formatToolUse(name: string, input: unknown): string {
  const inputStr = typeof input === 'string' ? input : JSON.stringify(input, null, 2)
  // Truncate long inputs
  const truncated = inputStr.length > 200 ? inputStr.slice(0, 200) + '...' : inputStr
  return `🔧 ${name}: ${truncated}`
}

interface RunConfig {
  mode: 'issue' | 'pr' | 'adhoc'
  id: string
  description: string
  prContext?: {
    originalIssue: string
    prSummary: string
    comments: string
  }
}

function parseArgs(): RunConfig {
  const args = process.argv.slice(2)

  // Check for --pr flag (adjust mode)
  const prIdx = args.indexOf('--pr')
  if (prIdx !== -1 && args[prIdx + 1]) {
    const id = args[prIdx + 1]
    const description = args.filter((_, i) => i !== prIdx && i !== prIdx + 1).join(' ')
    return { mode: 'pr', id, description }
  }

  // Check for --issue flag (new fix mode)
  const issueIdx = args.indexOf('--issue')
  if (issueIdx !== -1 && args[issueIdx + 1]) {
    const id = args[issueIdx + 1]
    const description = args.filter((_, i) => i !== issueIdx && i !== issueIdx + 1).join(' ')
    return { mode: 'issue', id, description }
  }

  // Generate adhoc ID for local testing
  const user = process.env.USER || 'unknown'
  const timestamp = Math.floor(Date.now() / 1000)
  const id = `adhoc-${user}-${timestamp}`
  const description = args.join(' ')
  return { mode: 'adhoc', id, description }
}

function fetchPRContext(prNumber: string): { issueId: string, originalIssue: string, prSummary: string, comments: string } {
  try {
    // Get PR body
    const prBody = execSync(`gh pr view ${prNumber} --json body -q .body`, { encoding: 'utf-8' }).trim()

    // Extract issue number from "Closes #N"
    const issueMatch = prBody.match(/Closes #(\d+)/i)
    const issueId = issueMatch?.[1] || prNumber

    // Get original issue
    let originalIssue = ''
    if (issueMatch) {
      try {
        const issueTitle = execSync(`gh issue view ${issueId} --json title -q .title`, { encoding: 'utf-8' }).trim()
        const issueBody = execSync(`gh issue view ${issueId} --json body -q .body`, { encoding: 'utf-8' }).trim()
        originalIssue = `#${issueId}: ${issueTitle}\n\n${issueBody}`
      } catch {
        originalIssue = `Issue #${issueId} (could not fetch details)`
      }
    }

    // Get PR comments
    const commentsJson = execSync(`gh pr view ${prNumber} --json comments -q '.comments[] | "\\(.author.login): \\(.body)"'`, { encoding: 'utf-8' }).trim()
    const comments = commentsJson || '(no comments yet)'

    // Extract summary from PR body (between ## Summary and next ##)
    const summaryMatch = prBody.match(/## Summary\n([\s\S]*?)(?=\n##|$)/)
    const prSummary = summaryMatch?.[1]?.trim() || prBody.slice(0, 500)

    return { issueId, originalIssue, prSummary, comments }
  } catch (e) {
    console.error('Failed to fetch PR context:', e)
    return { issueId: prNumber, originalIssue: '', prSummary: '', comments: '' }
  }
}

async function main() {
  const config = parseArgs()

  if (!config.description) {
    console.error('Usage:')
    console.error('  npm run fix -- --issue <number> "description"   # New fix')
    console.error('  npm run fix -- --pr <number> "adjustment"       # Adjust PR')
    console.error('  npm run fix -- "description"                    # Local test')
    process.exit(1)
  }

  let prompt: string
  let issueId: string

  if (config.mode === 'pr') {
    // Adjust mode - fetch context from existing PR
    console.log('🔄 Starting PR adjustment workflow...')
    console.log(`📋 PR: #${config.id}`)
    console.log(`📝 ${config.description}`)
    console.log('─'.repeat(60))
    console.log('Fetching PR context...')

    const ctx = fetchPRContext(config.id)
    issueId = ctx.issueId

    console.log(`  Original issue: #${issueId}`)
    console.log(`  Comments: ${ctx.comments.split('\n').length} messages`)
    console.log('─'.repeat(60))

    prompt = ADJUST_PROMPT
      .replace('{ORIGINAL_ISSUE}', ctx.originalIssue)
      .replace('{PR_SUMMARY}', ctx.prSummary)
      .replace('{COMMENTS}', ctx.comments)
      .replace('{ADJUSTMENT}', config.description)
      .replace(/{ISSUE_ID}/g, issueId)
  } else {
    // New fix mode
    issueId = config.id
    console.log('🔧 Starting verified fix workflow...')
    console.log(`📋 Issue: ${issueId}`)
    console.log(`📝 ${config.description}`)
    console.log('─'.repeat(60))

    prompt = WORKFLOW_PROMPT
      .replace('{ISSUE}', config.description)
      .replace(/{ISSUE_ID}/g, issueId)
  }

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
    claude.on('close', async (code) => {
      console.log('\n' + '─'.repeat(60))

      // Parse the PR content
      const prMatch = fullOutput.match(/---PR---([\s\S]*?)---END---/)
      if (prMatch) {
        const prBlock = prMatch[1]
        const titleMatch = prBlock.match(/title:\s*(.+)/)
        const statusMatch = prBlock.match(/status:\s*(success|failure)/)
        const videoMatch = prBlock.match(/demo_video:\s*(.+)/)
        const title = titleMatch?.[1]?.trim() || 'Fix'
        const status = statusMatch?.[1] || 'unknown'
        const videoPath = videoMatch?.[1]?.trim()

        // Extract the markdown body (everything after the header lines)
        const bodyMatch = prBlock.match(/demo_video:.*\n([\s\S]*)/)
        let body = bodyMatch?.[1]?.trim() || ''

        // Get issue ID from output
        const issueIdMatch = prBlock.match(/issue_id:\s*(.+)/)
        const prIssueId = issueIdMatch?.[1]?.trim() || 'unknown'

        // Convert video to GIF if we have one
        let gifPath: string | undefined
        if (videoPath && fs.existsSync(videoPath)) {
          console.log('🎬 Converting video to GIF...')
          const issueDir = path.join(process.cwd(), 'e2e', 'issues', prIssueId)
          fs.mkdirSync(issueDir, { recursive: true })
          gifPath = path.join(issueDir, 'demo.gif')
          try {
            execSync(`"${FFMPEG_PATH}" -y -i "${videoPath}" -vf "fps=12,scale=800:-1:flags=lanczos" -loop 0 "${gifPath}"`,
              { stdio: 'pipe' })
            console.log(`✓ GIF created: e2e/issues/${prIssueId}/demo.gif`)
            // Replace the demo placeholder with the actual GIF
            body = body.replace(/## Demo\n.*$/m, `## Demo\n![Demo](file://${gifPath})`)
          } catch (e) {
            console.log('⚠️  ffmpeg not available, skipping GIF conversion')
          }
        }

        // Write PR body markdown for CI
        const issueDir = path.join(process.cwd(), 'e2e', 'issues', prIssueId)
        fs.mkdirSync(issueDir, { recursive: true })
        const prBodyPath = path.join(issueDir, 'pr-body.md')
        fs.writeFileSync(prBodyPath, body)
        console.log(`📝 PR body written to: e2e/issues/${prIssueId}/pr-body.md`)

        // Generate HTML preview (skip in CI)
        if (!process.env.CI) {
          await generatePreview(title, body, status)
        }

        if (status === 'success') {
          console.log('✅ Fix verified successfully!')
          console.log('📄 PR preview opened in browser')
          process.exit(0)
        } else {
          console.log('❌ Fix verification failed')
          process.exit(1)
        }
      } else {
        // Check if there's an assertion bug report
        const bugMatch = fullOutput.match(/---ASSERTION_BUG---([\s\S]*?)---END_BUG---/)
        if (bugMatch) {
          console.log('🐛 ASSERTION SYSTEM BUG DETECTED')
          console.log('─'.repeat(40))
          console.log(bugMatch[1].trim())
          console.log('─'.repeat(40))
          console.log('')
          console.log('The visual assertion system returned an incorrect result.')
          console.log('Please investigate and fix the assertion logic.')
          process.exit(2)  // Special exit code for assertion bugs
        }

        console.log('⚠️  Workflow did not complete (no PR block found)')
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
