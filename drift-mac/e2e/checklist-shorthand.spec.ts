import { test, expect, type Page } from "@playwright/test";
import { previewMocks } from "./preview-mocks";

const title = "Checklist shorthand";
const saved = (page: Page) =>
  page.evaluate((name) => (window as any).__mockFS.get(name + ".md"), title);

test.beforeEach(async ({ page }) => {
  await page.addInitScript(previewMocks());
  await page.goto("/");
  await expect(page.locator(".cm-editor")).toBeVisible();
  await page.keyboard.insertText(title + "\n\n");
});

for (const shorthand of ["[]", "-[]", "- []", "  []", "  -[]"]) {
  test(`${JSON.stringify(shorthand)} and Space make a checklist ready for writing`, async ({
    page,
  }) => {
    await page.keyboard.type(shorthand);
    await page.keyboard.press("Space");
    await page.keyboard.type("First task");
    const indent = shorthand.startsWith("  ") ? "  " : "";
    await expect
      .poll(() => saved(page))
      .toBe(title + "\n\n" + indent + "- [ ] First task");
    // The resulting item participates in the existing checklist behavior.
    await page.keyboard.press("Meta+Enter");
    await expect
      .poll(() => saved(page))
      .toBe(title + "\n\n" + indent + "- [x] First task");
  });
}

test("undo restores the shorthand and redo restores the ready-to-type checklist", async ({
  page,
}) => {
  await page.keyboard.type("[]");
  await page.keyboard.press("Space");
  await expect.poll(() => saved(page)).toBe(title + "\n\n- [ ] ");
  await page.keyboard.press("Meta+z");
  await expect.poll(() => saved(page)).toBe(title + "\n\n[]");
  await page.keyboard.press("Meta+Shift+z");
  await expect.poll(() => saved(page)).toBe(title + "\n\n- [ ] ");
  await page.keyboard.type("Task");
  await expect.poll(() => saved(page)).toBe(title + "\n\n- [ ] Task");
  await page.keyboard.press("Meta+z");
  await expect.poll(() => saved(page)).toBe(title + "\n\n- [ ] ");
});

for (const prefix of ["Words []", "```\n[]", "    []"]) {
  test(`Space preserves literal shorthand in ${JSON.stringify(prefix)}`, async ({
    page,
  }) => {
    await page.keyboard.insertText(prefix);
    await page.keyboard.press("Space");
    await expect.poll(() => saved(page)).toBe(title + "\n\n" + prefix + " ");
  });
}

test("pasted shorthand remains literal", async ({ page }) => {
  await page.locator(".cm-content").evaluate((content) => {
    const data = new DataTransfer();
    data.setData("text/plain", "[] \n-[] ");
    content.dispatchEvent(
      new ClipboardEvent("paste", { bubbles: true, clipboardData: data }),
    );
  });
  await expect.poll(() => saved(page)).toBe(title + "\n\n[] \n-[] ");
});

test("replacing a selection with Space does not autoformat", async ({ page }) => {
  await page.keyboard.insertText("[]x");
  await page.keyboard.press("Shift+ArrowLeft");
  await page.keyboard.press("Space");
  await expect.poll(() => saved(page)).toBe(title + "\n\n[] ");
});
