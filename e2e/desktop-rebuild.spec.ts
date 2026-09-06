import { test, expect } from "@playwright/test";
import { previewMocks } from "./preview-mocks";
const long =
  "Field notes\n\n" +
  Array.from(
    { length: 90 },
    (_, i) =>
      `Paragraph ${i + 1}. A quiet notebook gives each thought room to breathe.`,
  ).join("\n\n") +
  "\n\nThe distant marmalade lighthouse.";
const seed = {
  "Field notes.md": long,
  "Shopping.md": "Shopping\n\nCoffee and bread",
  "Lists.md":
    "Lists\n\n* A long bullet that should continue aligned beneath its text when the window is narrow. ".repeat(
      8,
    ),
};
test.beforeEach(async ({ page }) => {
  await page.addInitScript(previewMocks(seed));
  await page.goto("/");
  await expect(page.locator(".cm-editor")).toBeVisible();
});
async function open(page: any, title: string) {
  await page.keyboard.press("Meta+p");
  await page.getByRole("combobox").fill(title);
  await page.keyboard.press("Enter");
  await expect(page.locator(".quick-open")).toHaveCount(0);
}
async function text(page: any, value: string) {
  await page.locator(".cm-content").focus();
  await page.keyboard.press("Meta+a");
  if (value) await page.keyboard.insertText(value);
  else await page.keyboard.press("Backspace");
}
const saved = (page: any, path: string) =>
  page.evaluate((p: string) => (window as any).__mockFS.get(p), path);

test("full text search opens a distant match and Escape restores focus", async ({
  page,
}) => {
  await open(page, "marmalade");
  await expect(page.locator(".cm-content")).toContainText("marmalade");
  await expect
    .poll(() => page.locator(".cm-scroller").evaluate((e) => e.scrollTop))
    .toBeGreaterThan(1000);
  await page.keyboard.press("Meta+p");
  await page.keyboard.press("Escape");
  await page.keyboard.insertText("replacement");
  await expect(page.locator(".cm-content")).toContainText("replacement");
});
test("typing through a slow save serializes all versions and renames once", async ({
  page,
}) => {
  await page.evaluate(() => {
    (window as any).__delay = 600;
  });
  await text(page, "First title\nbody");
  await page.waitForTimeout(500);
  await text(page, "Final title\nnewest writing");
  await expect
    .poll(() => saved(page, "Final title.md"))
    .toBe("Final title\nnewest writing");
  expect(
    await page.evaluate(() =>
      Array.from((window as any).__mockFS.keys()).filter((s: any) =>
        s.includes("title"),
      ),
    ),
  ).toEqual(["Final title.md"]);
});
test("clearing an existing note saves an empty file", async ({ page }) => {
  await open(page, "Shopping");
  await text(page, "");
  await expect.poll(() => saved(page, "Shopping.md")).toBe("");
});
test("empty new notes leave no files", async ({ page }) => {
  await page.keyboard.press("Meta+n");
  await page.keyboard.insertText("   ");
  await page.keyboard.press("Meta+n");
  expect(await page.evaluate(() => (window as any).__mockFS.size)).toBe(3);
});
test("switching notes flushes pending text and undo never crosses documents", async ({
  page,
}) => {
  await open(page, "Shopping");
  await page.keyboard.press("Meta+End");
  await page.keyboard.insertText(" and tea");
  await open(page, "Field notes");
  await page.keyboard.press("Meta+z");
  await page.keyboard.press("Meta+Home");
  await expect(page.locator(".cm-content")).toContainText("Field notes");
  expect(await saved(page, "Shopping.md")).toContain("and tea");
  await open(page, "Shopping");
  await page.keyboard.press("Meta+z");
  await expect
    .poll(() => saved(page, "Shopping.md"))
    .toBe("Shopping\n\nCoffee and bread");
});
test("save failure blocks navigation, keeps draft, and Retry works", async ({
  page,
}) => {
  await page.evaluate(() => {
    (window as any).__failSave = true;
  });
  await text(page, "Keep this\nImportant writing");
  await page.keyboard.press("Meta+n");
  await expect(page.getByRole("alert")).toContainText("Saving failed");
  await expect(page.locator(".cm-content")).toContainText("Important writing");
  expect(
    await page.evaluate(() =>
      Object.keys(localStorage).some((k) => k.includes("draft:")),
    ),
  ).toBe(true);
  await page.evaluate(() => {
    (window as any).__failSave = false;
  });
  await page.getByText("Retry save", { exact: true }).click();
  await expect
    .poll(() => saved(page, "Keep this.md"))
    .toContain("Important writing");
});
test("crash reload restores an unsaved recovery draft", async ({ page }) => {
  await page.evaluate(() => {
    (window as any).__failSave = true;
  });
  await text(page, "Recovered draft\nSurvives restart");
  await page.reload();
  await expect(page.locator(".cm-content")).toContainText("Survives restart");
});
test("a clean externally edited note reloads without writing over it", async ({
  page,
}) => {
  await open(page, "Shopping");
  await page.evaluate(() => {
    (window as any).__mockFS.set("Shopping.md", "Shopping\nChanged on phone");
    window.dispatchEvent(new Event("focus"));
  });
  await expect(page.locator(".cm-content")).toContainText("Changed on phone");
  await page.evaluate(() => window.dispatchEvent(new Event("blur")));
  expect(await saved(page, "Shopping.md")).toBe("Shopping\nChanged on phone");
  expect(await page.evaluate(() => (window as any).__writes.length)).toBe(0);
});
test("concurrent external edit preserves both versions", async ({ page }) => {
  await open(page, "Shopping");
  await text(page, "Shopping\nDesktop writing");
  await page.evaluate(() => {
    (window as any).__mockFS.set("Shopping.md", "Shopping\nPhone writing");
  });
  await expect
    .poll(() => saved(page, "Shopping (conflict).md"))
    .toBe("Shopping\nDesktop writing");
  expect(await saved(page, "Shopping.md")).toBe("Shopping\nPhone writing");
});
test("close waits for a slow save and failed close keeps window", async ({
  page,
}) => {
  await page.evaluate(() => {
    (window as any).__delay = 800;
  });
  await text(page, "Closing\nKeep every word");
  await page.evaluate(() => (window as any).__emit("menu-close-window"));
  await page.waitForTimeout(150);
  expect(await page.evaluate(() => (window as any).__destroyed)).toBe(false);
  await expect
    .poll(() => page.evaluate(() => (window as any).__destroyed))
    .toBe(true);
  expect(await saved(page, "Closing.md")).toContain("every word");
});
test("long note position returns after switching; find is quiet and functional", async ({
  page,
}) => {
  await open(page, "Field notes");
  await page.keyboard.press("Meta+End");
  const scroll = await page
    .locator(".cm-scroller")
    .evaluate((e) => e.scrollTop);
  await open(page, "Shopping");
  await open(page, "Field notes");
  await expect
    .poll(() => page.locator(".cm-scroller").evaluate((e) => e.scrollTop))
    .toBeGreaterThan(scroll - 100);
  await page.keyboard.press("Meta+f");
  await page
    .getByRole("textbox", { name: "Find in note", exact: true })
    .fill("Paragraph");
  await expect(page.locator(".search-count")).toContainText("90");
  await page.getByRole("button", { name: "Close find" }).click();
  await expect(page.locator(".cm-search")).toHaveCount(0);
});
test("bullets, checklists, multiline selection, and undo stay intact", async ({
  page,
}) => {
  await text(page, "A note\n\nalpha\nbeta");
  await page.keyboard.press("Meta+a");
  await page.keyboard.press("Meta+Shift+8");
  await expect(page.locator(".cm-content")).toContainText("* beta");
  await page.keyboard.press("Meta+z");
  await expect(page.locator(".cm-content")).toContainText("alpha");
  await page.keyboard.press("Meta+End");
  await page.keyboard.press("Meta+Shift+l");
  await page.keyboard.press("Meta+Enter");
  await expect(page.locator(".cm-content")).toContainText("- [x] beta");
});
test("visual notebook and search at normal and narrow sizes", async ({
  page,
}, info) => {
  await text(
    page,
    "A little room to think\n\nThe best tools disappear into the work.\n\n* A long thought can wrap across the page without losing its place or its comfortable hanging indent.\n- [ ] Leave room for the next idea\n\n## Tomorrow\n\nKeep the page simple, and the writing safe.",
  );
  await page.keyboard.press("Meta+Home");
  await page.screenshot({ path: info.outputPath("notebook.png") });
  await page.setViewportSize({ width: 430, height: 660 });
  await page.screenshot({ path: info.outputPath("narrow.png") });
  await page.keyboard.press("Meta+p");
  await page.getByRole("combobox").fill("marmalade");
  await expect(page.getByRole("option")).toHaveCount(1);
  await page.screenshot({ path: info.outputPath("search.png") });
});

test("metadata and opening stay available during a thousand-note index", async ({
  page,
}) => {
  await page.evaluate(() => {
    for (let i = 0; i < 1000; i++)
      (window as any).__mockFS.set(
        `Archive ${i}.md`,
        `Archive ${i}\n${"A long body. ".repeat(40)}`,
      );
    (window as any).__readDelay = 200;
    window.dispatchEvent(new Event("focus"));
  });
  await open(page, "Shopping");
  await expect(page.locator(".cm-content")).toContainText("Coffee and bread");
  await page.keyboard.press("Meta+End");
  await page.keyboard.insertText(" in town");
  await expect.poll(() => saved(page, "Shopping.md")).toContain("in town");
});
test("a failed close keeps the window and a failed quit never acknowledges readiness", async ({
  page,
}) => {
  await page.evaluate(() => {
    (window as any).__failSave = true;
  });
  await text(page, "Stay open\nUnsaved work");
  await page.evaluate(() => (window as any).__emit("menu-close-window"));
  await expect(page.getByRole("alert")).toBeVisible();
  expect(await page.evaluate(() => (window as any).__destroyed)).toBe(false);
  await page.evaluate(() => (window as any).__emit("prepare-quit"));
  await expect(page.getByRole("alert")).toContainText("stay open");
});
test("blank search navigation does not trap selection at a negative index", async ({
  page,
}) => {
  await page.keyboard.press("Meta+p");
  await page.getByRole("combobox").fill("nothing matches");
  await page.keyboard.press("ArrowDown");
  await page.keyboard.press("Tab");
  await page.getByRole("combobox").fill("Shopping");
  await page.keyboard.press("Enter");
  await expect(page.locator(".cm-content")).toContainText("Coffee and bread");
});
test("mixed links do not throw decoration-order errors and Cmd-click opens the link", async ({
  page,
}) => {
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await text(
    page,
    "Links\n\nhttps://example.com followed by [a link](https://openai.com) and **bold** text.",
  );
  await page.keyboard.press("Meta+Home");
  await page
    .locator('[data-url="https://example.com/"]')
    .click({ modifiers: ["Meta"] });
  expect(errors).toEqual([]);
  expect(await page.evaluate(() => (window as any).__openedUrls)).toEqual(["https://example.com/"]);
});

test('a large notebook renders a bounded set of rows and reaches the last result', async ({page}) => {
  await page.evaluate(() => { for(let i=0;i<1000;i++)(window as any).__mockFS.set(`Archive ${String(i).padStart(4,'0')}.md`,`Archive ${i}\nA thought`);window.dispatchEvent(new Event('focus')) })
  await page.keyboard.press('Meta+p')
  await page.getByRole('combobox').fill('Archive')
  await expect(page.getByRole('option')).toHaveCount(18)
  await page.locator('.quick-open-list').evaluate(el => {el.scrollTop=el.scrollHeight})
  await expect(page.getByRole('option').filter({hasText:'Archive 0999'})).toBeVisible()
  await page.getByRole('option').filter({hasText:'Archive 0999'}).click()
  await expect(page.locator('.cm-content')).toContainText('Archive 999')
})
