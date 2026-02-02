import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('demo: DOOM face gets damaged as you type', async ({ page }) => {
  test.slow()
  await page.setViewportSize({ width: 1200, height: 800 })
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Wait for editor to be ready
  await page.waitForTimeout(1000)

  // Click into the editor
  await page.locator('.cm-content').click()
  await page.waitForTimeout(500)

  // Type a title and wait to see the healthy face
  await page.keyboard.type('# DOOM Face Feature Demo', { delay: 40 })
  await page.waitForTimeout(1000)

  // Wait for DOOM face to appear
  await expect(page.locator('.doom-face-container')).toBeVisible()
  await page.waitForTimeout(1500)

  // Type a bit more to get to ~50-80 words (healthy face)
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.keyboard.type('Watch the DOOM face in the bottom right corner as I type. It starts healthy and happy, but as I write more and more words, it begins to take damage. ', { delay: 30 })
  await page.waitForTimeout(1500)

  // Type more to reach ~100-150 words (scratched face)
  await page.keyboard.type('This is kind of like a visual word count tracker, but way more fun! The face gets progressively more damaged as you approach the target word count. ', { delay: 30 })
  await page.waitForTimeout(1500)

  // Type more to reach ~200-250 words (bruised face)
  await page.keyboard.type('At around 200 words, you can see the face is starting to look pretty beaten up. The colors change from green to orange, showing that we\'re in the warning zone now. ', { delay: 30 })
  await page.waitForTimeout(1500)

  // Type more to reach ~300-350 words (bloodied face)
  await page.keyboard.type('As we continue typing even more content, the face takes even more damage. The ASCII art changes to show more battle scars and injuries. ', { delay: 30 })
  await page.waitForTimeout(1500)

  // Type more to reach ~400-450 words (beaten face)
  await page.keyboard.type('Keep going and the poor DOOM guy is really getting beaten up now. The face shows signs of serious damage with X\'s for eyes. ', { delay: 30 })
  await page.waitForTimeout(1500)

  // Type more to reach ~500-550 words (dead face)
  await page.keyboard.type('At this point, the face turns orange-red to indicate danger levels. We\'re getting close to the 600 word mark. ', { delay: 30 })
  await page.waitForTimeout(1500)

  // Hover over the face to show the full opacity
  await page.locator('.doom-face-container').hover()
  await page.waitForTimeout(2000)

  // Final pause to admire the damage
  await page.waitForTimeout(1000)
})
