import { test, expect, type Page } from "@playwright/test";
import { previewMocks } from "./preview-mocks";

const address = "https://example.com/research/a-long-address-that-wraps-across-the-page?full=true";
const fixture = `Selection gestures\n\nBefore ${address} after the address.\n\n- [ ] Checklist text\n\nFinal paragraph to select.`;

async function openNote(page: Page, text = fixture) {
  await page.addInitScript(previewMocks({ "Selection gestures.md": text }));
  await page.goto("/");
  await expect.poll(() => page.evaluate(() => (window as any).__presented)).toBe(true);
  await page.keyboard.press("Meta+p");
  await page.getByRole("combobox").fill("Selection gestures");
  await page.keyboard.press("Enter");
  await expect(page.locator(".quick-open")).toHaveCount(0);
  await page.evaluate(async () => {
    await document.fonts.ready;
    const modulePath = "/node_modules/.vite/deps/@codemirror_view.js";
    const { EditorView } = await import(modulePath);
    (window as any).__gestureView = EditorView.findFromDOM(document.querySelector(".cm-content"));
  });
}

async function copiedText(page: Page) {
  return page.locator(".cm-content").evaluate((el) => {
    const data = new DataTransfer();
    el.dispatchEvent(new ClipboardEvent("copy", {
      clipboardData: data, bubbles: true, cancelable: true,
    }));
    return data.getData("text/plain");
  });
}

for (const kind of ["bare", "named"]) {
  test(`dragging from a compact ${kind} address selects exact source text`, async ({ page }) => {
    const text = kind === "bare" ? fixture : fixture.replace(address, `[Research](${address})`);
    await openNote(page, text);
    const sourceOffset = 12;
    const start = await page.locator("[data-compact-text]").evaluate((el, offset) => {
      const range = document.createRange();
      range.setStart(el.firstChild!, offset - 8);
      range.setEnd(el.firstChild!, offset - 8 + 1);
      const box = range.getBoundingClientRect();
      return { x: box.left + 1, y: (box.top + box.bottom) / 2 };
    }, sourceOffset);
    await page.mouse.move(start.x, start.y);
    await page.mouse.down();
    await expect(page.locator("[data-compact-link]")).toHaveCount(0);
    const head = text.indexOf("Final paragraph") + "Final paragraph".length;
    const end = await page.evaluate((pos) => {
      const rect = (window as any).__gestureView.coordsAtPos(pos);
      return { x: rect.left, y: (rect.top + rect.bottom) / 2 };
    }, head);
    await page.mouse.move(end.x, end.y, { steps: 15 });
    await page.mouse.up();
    await expect.poll(() => copiedText(page)).toBe(text.slice(text.indexOf(address) + sourceOffset, head));
    expect(await page.evaluate(() => (window as any).__openedUrls)).toEqual([]);
  });
}

for (const clickCount of [2, 3]) {
  test(`${clickCount === 2 ? "double" : "triple"}-clicking a compact link keeps word and line selection available`, async ({ page }) => {
    await openNote(page);
    const point = await page.locator("[data-compact-text]").evaluate((el) => {
      const range = document.createRange();
      range.setStart(el.firstChild!, 4);
      range.setEnd(el.firstChild!, 5);
      const box = range.getBoundingClientRect();
      return { x: box.left + 1, y: (box.top + box.bottom) / 2 };
    });
    await page.mouse.click(point.x, point.y, { clickCount });
    const selected = await copiedText(page);
    if (clickCount === 2) expect(selected).toMatch(/^\w+$/);
    else expect(selected).toContain("Before https://example.com");
    expect(await page.evaluate(() => (window as any).__gestureView.state.selection.main.empty)).toBe(false);
    expect(await page.evaluate(() => (window as any).__gestureView.state.doc.toString())).toBe(fixture);
    expect(await page.evaluate(() => (window as any).__openedUrls)).toEqual([]);
  });
}

test("Shift-clicking a checkbox extends selection without checking it", async ({ page }) => {
  await openNote(page);
  await page.keyboard.press("Meta+Home");
  await page.locator(".checkbox-marker").click({ modifiers: ["Shift"] });
  expect(await page.evaluate(() => (window as any).__gestureView.state.doc.toString())).toBe(fixture);
  expect(await copiedText(page)).toContain("Selection gestures\n\nBefore");
});

test("right-clicking a checkbox does not change the note", async ({ page }) => {
  await openNote(page);
  const anchor = fixture.indexOf("Checklist text");
  await page.evaluate((anchor) => {
    (window as any).__gestureView.dispatch({ selection: { anchor, head: anchor + 9 } });
  }, anchor);
  await page.locator(".checkbox-marker").click({ button: "right" });
  expect(await page.evaluate(() => (window as any).__gestureView.state.doc.toString())).toBe(fixture);
});

test("a drag starting in a compact link keeps selecting through edge scrolling and reversal", async ({ page }) => {
  await page.setViewportSize({ width: 600, height: 750 });
  const text = fixture + "\n\n" + Array.from({ length: 80 }, (_, i) =>
    `Paragraph ${i}. ${"A long note stays easy to select and copy. ".repeat(4)}`,
  ).join("\n\n");
  await openNote(page, text);
  const anchor = text.indexOf(address) + 12;
  const start = await page.locator("[data-compact-text]").evaluate((el) => {
    const range = document.createRange();
    range.setStart(el.firstChild!, 4);
    range.setEnd(el.firstChild!, 5);
    const box = range.getBoundingClientRect();
    return { x: box.left + 1, y: (box.top + box.bottom) / 2 };
  });
  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  await page.mouse.move(280, 738, { steps: 20 });
  await expect.poll(() => page.locator(".cm-scroller").evaluate(el => el.scrollTop)).toBeGreaterThan(200);
  const forwardHead = await page.evaluate(() => (window as any).__gestureView.state.selection.main.head);
  expect(forwardHead).toBeGreaterThan(anchor);
  await page.mouse.move(280, 45, { steps: 15 });
  await expect.poll(() => page.evaluate(() => (window as any).__gestureView.state.selection.main.head)).toBeLessThan(forwardHead);
  await page.mouse.move(280, 300, { steps: 8 });
  await page.mouse.up();
  const selection = await page.evaluate(() => {
    const range = (window as any).__gestureView.state.selection.main;
    return { anchor: range.anchor, head: range.head, from: range.from, to: range.to };
  });
  expect(selection.anchor).toBe(anchor);
  expect(selection.to - selection.from).toBeGreaterThan(20);
  expect(await copiedText(page)).toBe(text.slice(selection.from, selection.to));
  await page.mouse.wheel(0, 1600);
  await expect.poll(() => page.locator(".cm-scroller").evaluate(el => el.scrollTop)).toBeGreaterThan(1000);
  expect(await copiedText(page)).toBe(text.slice(selection.from, selection.to));
  expect(await page.evaluate(() => (window as any).__gestureView.state.doc.toString())).toBe(text);
});

for (const location of ["before", "after"]) {
  test(`an external edit ${location} selected text preserves the selection and exact copy`, async ({ page }) => {
    await openNote(page);
    const selected = "Final paragraph";
    const anchor = fixture.indexOf(selected) + selected.length;
    const head = fixture.indexOf(selected);
    await page.evaluate(({ anchor, head }) => {
      (window as any).__gestureView.dispatch({ selection: { anchor, head } });
    }, { anchor, head });
    const updated = location === "before"
      ? fixture.replace("Before ", "New phone writing.\n\nBefore ")
      : fixture + "\n\nNew phone writing.";
    await page.evaluate((text) => {
      (window as any).__mockFS.set("Selection gestures.md", text);
      window.dispatchEvent(new Event("focus"));
    }, updated);
    await expect.poll(() => page.evaluate(() => (window as any).__gestureView.state.doc.toString())).toBe(updated);
    expect(await copiedText(page)).toBe(selected);
    const selection = await page.evaluate(() => {
      const range = (window as any).__gestureView.state.selection.main;
      return { anchor: range.anchor, head: range.head };
    });
    expect(selection.anchor).toBeGreaterThan(selection.head);
    expect(await page.evaluate(() => (window as any).__writes)).toEqual([]);
  });
}

test("selection undo and redo stay mapped through a clean external edit", async ({ page }) => {
  await openNote(page);
  await page.evaluate((text) => {
    const view = (window as any).__gestureView;
    const first = text.indexOf("Checklist text");
    const second = text.indexOf("Final paragraph");
    view.dispatch({ selection: { anchor: first, head: first + "Checklist text".length } });
    view.dispatch({ selection: { anchor: second, head: second + "Final paragraph".length } });
  }, fixture);
  const updated = fixture.replace("Before ", "New phone writing.\n\nBefore ");
  await page.evaluate((text) => {
    (window as any).__mockFS.set("Selection gestures.md", text);
    window.dispatchEvent(new Event("focus"));
  }, updated);
  await expect.poll(() => page.evaluate(() => (window as any).__gestureView.state.doc.toString())).toBe(updated);
  await page.keyboard.press("Meta+u");
  expect(await copiedText(page)).toBe("Checklist text");
  await page.keyboard.press("Meta+Shift+u");
  expect(await copiedText(page)).toBe("Final paragraph");
  expect(await page.evaluate(() => (window as any).__gestureView.state.doc.toString())).toBe(updated);
  expect(await page.evaluate(() => (window as any).__writes)).toEqual([]);
});

test("undoing a saved local edit preserves an unrelated remote edit", async ({ page }) => {
  await openNote(page);
  await page.evaluate((text) => {
    const anchor = text.indexOf("Final paragraph");
    (window as any).__gestureView.dispatch({ selection: { anchor, head: anchor + "Final paragraph".length } });
  }, fixture);
  await page.keyboard.insertText("Local writing");
  const edited = fixture.replace("Final paragraph", "Local writing");
  await expect.poll(() => page.evaluate(() => (window as any).__mockFS.get("Selection gestures.md"))).toBe(edited);
  const remote = edited.replace("Before ", "Remote words. Before ");
  await page.evaluate((text) => {
    (window as any).__mockFS.set("Selection gestures.md", text);
    window.dispatchEvent(new Event("focus"));
  }, remote);
  await expect.poll(() => page.evaluate(() => (window as any).__gestureView.state.doc.toString())).toBe(remote);
  await page.keyboard.press("Meta+z");
  expect(await page.evaluate(() => (window as any).__gestureView.state.doc.toString())).toBe(fixture.replace("Before ", "Remote words. Before "));
  await page.keyboard.press("Meta+Shift+z");
  expect(await page.evaluate(() => (window as any).__gestureView.state.doc.toString())).toBe(remote);
});

test("an external replacement covering a selection leaves a valid caret for typing", async ({ page }) => {
  await openNote(page);
  await page.evaluate((text) => {
    const anchor = text.indexOf("Checklist text");
    (window as any).__gestureView.dispatch({ selection: { anchor, head: anchor + "Checklist text".length } });
  }, fixture);
  const updated = fixture.replace("Before ", "New phone writing. Before ") + "\nPhone ending.";
  await page.evaluate((text) => {
    (window as any).__mockFS.set("Selection gestures.md", text);
    window.dispatchEvent(new Event("focus"));
  }, updated);
  await expect.poll(() => page.evaluate(() => (window as any).__gestureView.state.doc.toString())).toBe(updated);
  const range = await page.evaluate(() => {
    const range = (window as any).__gestureView.state.selection.main;
    return { from: range.from, to: range.to, head: range.head };
  });
  expect(range.from).toBeLessThanOrEqual(range.to);
  await page.keyboard.insertText("Typed");
  expect(await page.evaluate(() => (window as any).__gestureView.state.doc.toString()))
    .toBe(updated.slice(0, range.from) + "Typed" + updated.slice(range.to));
});

test("selection undo after a covering external replacement leaves copy and typing safe", async ({ page }) => {
  await openNote(page);
  await page.evaluate((text) => {
    const view = (window as any).__gestureView;
    for (const selected of ["Checklist text", "Final paragraph"]) {
      const anchor = text.indexOf(selected);
      view.dispatch({ selection: { anchor, head: anchor + selected.length } });
    }
  }, fixture);
  const updated = fixture.replace("Before ", "New phone writing. Before ") + "\nPhone ending.";
  await page.evaluate((text) => {
    (window as any).__mockFS.set("Selection gestures.md", text);
    window.dispatchEvent(new Event("focus"));
  }, updated);
  await expect.poll(() => page.evaluate(() => (window as any).__gestureView.state.doc.toString())).toBe(updated);
  for (const command of ["Meta+u", "Meta+Shift+u", "Meta+u"]) {
    await page.keyboard.press(command);
    const state = await page.evaluate(() => {
      const view = (window as any).__gestureView;
      const range = view.state.selection.main;
      return { from: range.from, to: range.to, line: view.state.doc.lineAt(range.head).text };
    });
    expect(state.from).toBe(state.to);
    expect(await copiedText(page)).toBe(state.line);
    expect(await page.evaluate(() => (window as any).__gestureView.state.doc.toString())).toBe(updated);
  }
  const position = await page.evaluate(() => (window as any).__gestureView.state.selection.main.head);
  await page.keyboard.insertText("Typed");
  expect(await page.evaluate(() => (window as any).__gestureView.state.doc.toString()))
    .toBe(updated.slice(0, position) + "Typed" + updated.slice(position));
});
