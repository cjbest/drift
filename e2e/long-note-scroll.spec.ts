import { test, expect } from '@playwright/test'
import { getTauriMockScript } from './tauri-mocks'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

// Helper: read the .cm-scroller scrollTop.
async function getScrollTop(page: import('@playwright/test').Page): Promise<number> {
  return page.evaluate(() => {
    const el = document.querySelector('.cm-scroller') as HTMLElement
    return el.scrollTop
  })
}

test('viewport scrolls through a 100-line note', async ({ page }) => {
  test.slow()
  await page.setViewportSize({ width: 900, height: 600 })
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Build the 100-line note content.
  const lines: string[] = ['Long Note Scroll Test']
  for (let i = 1; i <= 99; i++) {
    lines.push(`Line ${String(i).padStart(3, '0')} — quick brown fox jumps over the lazy dog`)
  }
  const noteContent = lines.join('\n')

  await page.locator('.cm-content').click()
  await page.keyboard.insertText(noteContent)
  await expect(page.locator('.cm-content')).toContainText('Line 099', { timeout: 10000 })

  // Sanity check: doc is taller than the viewport.
  const scrollMetrics = await page.evaluate(() => {
    const el = document.querySelector('.cm-scroller') as HTMLElement
    return { scrollHeight: el.scrollHeight, clientHeight: el.clientHeight }
  })
  expect(scrollMetrics.scrollHeight).toBeGreaterThan(scrollMetrics.clientHeight)

  await page.locator('.cm-content').click()
  await page.waitForTimeout(200)

  // Move cursor to the top — should bring viewport to top.
  await page.keyboard.press('Meta+ArrowUp')
  await page.waitForTimeout(300)

  // Bulk scroll: PageDown a bunch.
  for (let i = 0; i < 12; i++) {
    await page.keyboard.press('PageDown')
    await page.waitForTimeout(200)
  }
  const afterPageDown = await getScrollTop(page)
  expect(afterPageDown).toBeGreaterThan(200)

  // Bulk scroll back: PageUp a bunch.
  for (let i = 0; i < 12; i++) {
    await page.keyboard.press('PageUp')
    await page.waitForTimeout(200)
  }

  // Mouse-wheel scroll for completeness.
  const scroller = page.locator('.cm-scroller')
  await scroller.hover()
  for (let i = 0; i < 8; i++) {
    await page.mouse.wheel(0, 400)
    await page.waitForTimeout(180)
  }

  await page.waitForTimeout(500)
})

test('typing only scrolls viewport when cursor would move off-screen', async ({ page }) => {
  test.slow()
  await page.setViewportSize({ width: 900, height: 600 })
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Seed the same 100-line note.
  const lines: string[] = ['Long Note Scroll Test']
  for (let i = 1; i <= 99; i++) {
    lines.push(`Line ${String(i).padStart(3, '0')} — quick brown fox jumps over the lazy dog`)
  }
  await page.locator('.cm-content').click()
  await page.keyboard.insertText(lines.join('\n'))
  await expect(page.locator('.cm-content')).toContainText('Line 099', { timeout: 10000 })

  // Move to top and let things settle.
  await page.keyboard.press('Meta+ArrowUp')
  await page.waitForTimeout(300)

  // ─── Case A: clicking a visible line in the middle should not change scrollTop ────
  // First scroll so a chunk of mid-document lines are on screen.
  const scroller = page.locator('.cm-scroller')
  await scroller.hover()
  for (let i = 0; i < 4; i++) {
    await page.mouse.wheel(0, 400)
    await page.waitForTimeout(180)
  }
  await page.waitForTimeout(400)
  const beforeFocusClick = await getScrollTop(page)

  // Find a .cm-line whose bbox lies comfortably inside the visible viewport, and click it.
  const targetLineBoxA = await page.evaluate(() => {
    const scroller = document.querySelector('.cm-scroller') as HTMLElement
    const rect = scroller.getBoundingClientRect()
    const lines = Array.from(scroller.querySelectorAll('.cm-line')) as HTMLElement[]
    const midY = rect.top + rect.height / 2
    let best: HTMLElement | null = null
    let bestDist = Infinity
    for (const l of lines) {
      const r = l.getBoundingClientRect()
      if (r.top < rect.top + 50 || r.bottom > rect.bottom - 50) continue
      const d = Math.abs((r.top + r.bottom) / 2 - midY)
      if (d < bestDist) {
        bestDist = d
        best = l
      }
    }
    if (!best) return null
    const r = best.getBoundingClientRect()
    return { x: r.left + 50, y: r.top + r.height / 2 }
  })
  expect(targetLineBoxA).not.toBeNull()
  await page.mouse.click(targetLineBoxA!.x, targetLineBoxA!.y)
  await page.waitForTimeout(500)
  const afterFocusClick = await getScrollTop(page)
  expect(Math.abs(afterFocusClick - beforeFocusClick)).toBeLessThan(5)

  // ─── Case B: typing while cursor is mid-viewport should not move the viewport ────
  // We're already focused on a mid-viewport line — type a few characters and check.
  const beforeMidType = await getScrollTop(page)
  await page.keyboard.type('zzz typing here ', { delay: 50 })
  await page.waitForTimeout(400)
  const afterMidType = await getScrollTop(page)
  expect(Math.abs(afterMidType - beforeMidType)).toBeLessThan(5)

  // Undo the inserted characters so the next case is clean.
  for (let i = 0; i < 16; i++) {
    await page.keyboard.press('Backspace')
  }
  await page.waitForTimeout(300)

  // ─── Case C: typing that pushes the cursor below the viewport must scroll ────
  // Jump to end of document so cursor is on the last visible line at the very bottom.
  await page.keyboard.press('Meta+ArrowDown')
  await page.waitForTimeout(400)
  const beforeBottomType = await getScrollTop(page)
  // Press Enter several times — each new line pushes the cursor down.
  for (let i = 0; i < 6; i++) {
    await page.keyboard.press('Enter')
    await page.keyboard.type('typing past bottom ' + i, { delay: 40 })
  }
  await page.waitForTimeout(500)
  const afterBottomType = await getScrollTop(page)
  expect(afterBottomType).toBeGreaterThan(beforeBottomType)

  await page.waitForTimeout(500)
})
