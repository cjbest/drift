import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('demo: beautiful typography in light and dark mode', async ({ page }) => {
  test.slow()

  // Use a compact viewport
  await page.setViewportSize({ width: 600, height: 450 })

  // Start in light mode
  await page.addInitScript(() => {
    localStorage.setItem('drift-theme', 'light')
  })

  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()
  await page.waitForTimeout(800)

  // Create a beautiful sample document
  await page.locator('.cm-content').click()

  // Title with elegant serif
  await page.keyboard.type('The Art of Typography', { delay: 40 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(400)

  // Body text showing beautiful serif font
  await page.keyboard.type('Great typography is invisible. It does not call attention to itself, but rather enhances the reading experience through careful attention to spacing, weight, and form.', { delay: 35 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(400)

  // Show emphasis
  await page.keyboard.type('Notice how ', { delay: 40 })
  await page.keyboard.type('**bold text**', { delay: 40 })
  await page.keyboard.type(' and ', { delay: 40 })
  await page.keyboard.type('*italic text*', { delay: 40 })
  await page.keyboard.type(' maintain the elegant character.', { delay: 35 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(400)

  // Heading hierarchy
  await page.keyboard.type('# Large Heading', { delay: 40 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('## Medium Heading', { delay: 40 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('### Small Heading', { delay: 40 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(400)

  // Blockquote showing italic elegance
  await page.keyboard.type('> "Typography is the craft of endowing human language with a durable visual form."', { delay: 35 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(800)

  // Scroll up to show everything
  await page.keyboard.press('Home')
  await page.waitForTimeout(1000)

  // Switch to dark mode to showcase the same elegance
  await page.keyboard.press('Meta+d')
  await page.waitForTimeout(1500)

  // Scroll down slightly to show content
  await page.keyboard.press('ArrowDown')
  await page.keyboard.press('ArrowDown')
  await page.keyboard.press('ArrowDown')
  await page.waitForTimeout(1000)

  // Back to light
  await page.keyboard.press('Meta+d')
  await page.waitForTimeout(1500)
})
