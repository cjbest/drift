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
  await page.keyboard.type('The Art of Typography', { delay: 35 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(300)

  // Body text showing beautiful serif font
  await page.keyboard.type('Great typography is invisible. It does not call attention to itself, but rather enhances the reading experience through careful attention to spacing, weight, and form.', { delay: 25 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(300)

  // Show emphasis
  await page.keyboard.type('Notice how ', { delay: 30 })
  await page.keyboard.type('**bold text**', { delay: 30 })
  await page.keyboard.type(' and ', { delay: 30 })
  await page.keyboard.type('*italic text*', { delay: 30 })
  await page.keyboard.type(' maintain the elegant character.', { delay: 25 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(300)

  // Heading hierarchy
  await page.keyboard.type('# Primary Heading', { delay: 35 })
  await page.keyboard.press('Enter')
  await page.waitForTimeout(200)
  await page.keyboard.type('Clear hierarchy and excellent spacing create visual rhythm.', { delay: 25 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(300)

  await page.keyboard.type('## Secondary Heading', { delay: 35 })
  await page.keyboard.press('Enter')
  await page.waitForTimeout(200)
  await page.keyboard.type('The refined weight and letter-spacing make headings distinct yet harmonious.', { delay: 25 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(300)

  await page.keyboard.type('### Tertiary Heading', { delay: 35 })
  await page.keyboard.press('Enter')
  await page.waitForTimeout(200)
  await page.keyboard.type('Even the smallest headings maintain clarity and elegance.', { delay: 25 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(300)

  // Lists showing vertical rhythm
  await page.keyboard.type('- [ ] Clean task items with perfect alignment', { delay: 25 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('- [ ] Proper spacing between list elements', { delay: 25 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('- [x] Beautiful checkboxes', { delay: 25 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(300)

  // Blockquote showing italic elegance
  await page.keyboard.type('> "Typography is the craft of endowing human language with a durable visual form."', { delay: 25 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(500)

  // More body text to show reading comfort
  await page.keyboard.type('The Charter and Georgia serif fonts provide exceptional readability for long-form content. Notice the comfortable line height, subtle letter-spacing, and overall typographic color that make extended reading sessions a pleasure.', { delay: 25 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(800)

  // Scroll to top to show the full document
  await page.keyboard.press('Meta+Home')
  await page.waitForTimeout(1200)

  // Slowly scroll through the content
  await page.keyboard.press('PageDown')
  await page.waitForTimeout(800)
  await page.keyboard.press('PageDown')
  await page.waitForTimeout(800)

  // Scroll back to top
  await page.keyboard.press('Meta+Home')
  await page.waitForTimeout(800)

  // Switch to dark mode to showcase the same elegance
  await page.keyboard.press('Meta+d')
  await page.waitForTimeout(1500)

  // Scroll through content in dark mode
  await page.keyboard.press('PageDown')
  await page.waitForTimeout(800)
  await page.keyboard.press('PageDown')
  await page.waitForTimeout(800)

  // Back to top in dark mode
  await page.keyboard.press('Meta+Home')
  await page.waitForTimeout(800)

  // Back to light to end
  await page.keyboard.press('Meta+d')
  await page.waitForTimeout(1500)
})
