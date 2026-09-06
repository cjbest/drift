import { test, expect } from '@playwright/test'
import { getTauriMockScript } from './tauri-mocks'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('bullet indent is consistent on wrapped lines', async ({ page }, info) => {
  await page.setViewportSize({ width: 600, height: 800 })

  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()
  await page.locator('.cm-content').click()

  // Type a title
  await page.keyboard.type('Meeting Notes')
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')

  // Type a long bullet that will wrap multiple times
  await page.keyboard.type('- ')
  const longText = 'This is a long bullet point that spans multiple lines. We need enough text here to ensure it wraps to at least three or four lines in the editor window to test the indent behavior.'
  await page.keyboard.type(longText)

  // Get the bullet line element
  const bulletLine = page.locator('.cm-line').filter({ hasText: 'This is a long bullet' })
  await expect(bulletLine).toBeVisible()

  // Measure rendered text boxes so the assertion also catches wrapping bugs
  // when the expected CSS is present but the browser lays it out incorrectly.
  await expect(async () => {
    const rows = await bulletLine.evaluate((line, body) => {
      const bodyStart = (line.textContent ?? '').indexOf(body)
      if (bodyStart < 0) throw new Error('Bullet text was not found')

      const rows: { top: number; left: number }[] = []
      const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT)
      let offset = 0
      let node: Node | null
      while ((node = walker.nextNode())) {
        const text = node.textContent ?? ''
        const start = Math.max(0, bodyStart - offset)
        const end = Math.min(text.length, bodyStart + body.length - offset)
        if (start < end) {
          const range = document.createRange()
          range.setStart(node, start)
          range.setEnd(node, end)
          for (const rect of range.getClientRects()) {
            if (!rect.width || !rect.height) continue
            const row = rows.find(row => Math.abs(row.top - rect.top) < 1)
            if (row) row.left = Math.min(row.left, rect.left)
            else rows.push({ top: rect.top, left: rect.left })
          }
        }
        offset += text.length
      }
      return rows
    }, longText)

    expect(rows.length, 'The bullet should wrap to at least three rows').toBeGreaterThanOrEqual(3)
    for (const row of rows.slice(1)) {
      expect(Math.abs(row.left - rows[0].left), 'Continuation text should align with the first row after the dash').toBeLessThan(1)
    }
  }).toPass({ timeout: 5000 })

  await page.screenshot({ path: info.outputPath('wrapped-bullet-indent-correct.png') })
})
