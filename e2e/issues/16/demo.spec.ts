import { test, expect } from '@playwright/test'
import { getTauriMockScript } from '../../tauri-mocks'

test.beforeEach(async ({ page }) => {
  await page.addInitScript(getTauriMockScript())
})

test('demo: minimap navigation', async ({ page }) => {
  test.slow()

  // Use a compact viewport
  await page.setViewportSize({ width: 800, height: 600 })
  await page.goto('/')
  await expect(page.locator('.cm-editor')).toBeVisible()

  // Click into editor
  await page.locator('.cm-content').click()
  await page.waitForTimeout(500)

  // Type a document title
  await page.keyboard.type('Meeting Notes 2026', { delay: 40 })
  await page.waitForTimeout(300)

  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(200)

  // Add first section
  await page.keyboard.type('## Attendees', { delay: 40 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('- Alice from Engineering', { delay: 40 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('- Bob from Design', { delay: 40 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('- Carol from Product', { delay: 40 })
  await page.waitForTimeout(500)

  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')

  // Add agenda section
  await page.keyboard.type('## Agenda', { delay: 40 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('1. Review Q1 roadmap', { delay: 40 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('2. Discuss new feature proposals', { delay: 40 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('3. Team updates', { delay: 40 })
  await page.waitForTimeout(500)

  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')

  // Add discussion section with more content
  await page.keyboard.type('## Discussion Points', { delay: 40 })
  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')
  await page.keyboard.type('### Q1 Roadmap', { delay: 40 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('The team reviewed the Q1 roadmap and agreed on priorities.', { delay: 40 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('Focus areas include performance improvements and mobile support.', { delay: 40 })
  await page.waitForTimeout(500)

  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')

  await page.keyboard.type('### New Features', { delay: 40 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('Several proposals were discussed including collaboration tools.', { delay: 40 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('The team will prototype these concepts next sprint.', { delay: 40 })
  await page.waitForTimeout(500)

  await page.keyboard.press('Enter')
  await page.keyboard.press('Enter')

  // Add action items
  await page.keyboard.type('## Action Items', { delay: 40 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('- [ ] Alice: Update technical specs', { delay: 40 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('- [ ] Bob: Create mockups', { delay: 40 })
  await page.keyboard.press('Enter')
  await page.keyboard.type('- [ ] Carol: Schedule follow-up', { delay: 40 })
  await page.waitForTimeout(800)

  // Wait for minimap to render fully
  await expect(page.locator('.minimap')).toBeVisible()
  await page.waitForTimeout(500)

  // Demonstrate scrolling - the minimap should show viewport position
  await page.keyboard.press('PageDown')
  await page.waitForTimeout(800)

  await page.keyboard.press('PageDown')
  await page.waitForTimeout(800)

  // Scroll back up
  await page.keyboard.press('Home')
  await page.waitForTimeout(800)

  // Demonstrate clicking minimap to jump to a section
  // Click near the bottom of the minimap to jump to the end
  const minimap = page.locator('.minimap')
  const minimapBox = await minimap.boundingBox()
  if (minimapBox) {
    // Click near the bottom (80% down)
    await page.mouse.click(
      minimapBox.x + minimapBox.width / 2,
      minimapBox.y + minimapBox.height * 0.8
    )
    await page.waitForTimeout(1000)

    // Click near the top to jump back
    await page.mouse.click(
      minimapBox.x + minimapBox.width / 2,
      minimapBox.y + minimapBox.height * 0.2
    )
    await page.waitForTimeout(1000)
  }

  // Final pause to show the minimap
  await page.waitForTimeout(500)
})
