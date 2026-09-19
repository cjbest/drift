// Shared with iOS: the reserved suffix keeps a pin attached to its Markdown file.
const pinnedSuffix = ".pinned.md";

export function isPinnedPath(path: string): boolean {
  return path.toLowerCase().endsWith(pinnedSuffix);
}

export function filenameTitle(path: string): string {
  return path.slice(0, isPinnedPath(path) ? -pinnedSuffix.length : -3);
}
