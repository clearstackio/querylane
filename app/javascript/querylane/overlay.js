// Paints the decorative overlay behind the transparent input text: operator
// keys coloured, masked runs shown as dots (same width: the font is
// monospace), the server's error range underlined. Uses textContent only.
const TOKEN = /(-?)([A-Za-z][A-Za-z0-9_]*:)|\b(OR|NOT)\b|([()])/g

export function paint(overlay, input, { mask = "", error = null } = {}) {
  const text = input.value
  // One entry per UTF-16 unit, matching regexp indexes and input positions.
  const classes = Array.from({ length: text.length }, () => new Set())

  for (const match of text.matchAll(TOKEN)) {
    const start = match.index + (match[1] ? match[1].length : 0)
    const kind = match[2] ? "ql-tok-key" : "ql-tok-op"
    if (match[1]) classes[match.index].add("ql-tok-op")
    for (let i = start; i < match.index + match[0].length; i++) classes[i].add(kind)
  }
  if (mask) {
    for (const match of text.matchAll(new RegExp(mask, "g"))) {
      for (let i = match.index; i < match.index + match[0].length; i++) if (/[0-9A-Za-z]/.test(text[i])) classes[i].add("ql-tok-mask")
    }
  }
  if (error) for (let i = error[0]; i < Math.min(error[1], text.length); i++) classes[i].add("ql-tok-error")

  overlay.replaceChildren(...runs(text, classes))
  overlay.scrollLeft = input.scrollLeft
}

function runs(text, classes) {
  const spans = []
  let start = 0
  for (let i = 1; i <= text.length; i++) {
    if (i < text.length && same(classes[i], classes[start])) continue
    const span = document.createElement("span")
    const names = Array.from(classes[start])
    if (names.length) span.className = names.join(" ")
    const chunk = text.slice(start, i)
    span.textContent = names.includes("ql-tok-mask") ? chunk.replace(/[0-9A-Za-z]/g, "•") : chunk
    spans.push(span)
    start = i
  }
  return spans
}

function same(a, b) {
  return a.size === b.size && [...a].every((name) => b.has(name))
}
