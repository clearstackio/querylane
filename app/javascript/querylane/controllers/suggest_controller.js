import { Controller } from "@hotwired/stimulus"
import Combobox from "@github/combobox-nav"

// A search box with suggestions (header dropdown or ⌘K palette). Typing posts
// the text into the list frame (debounced, stale answers dropped); ↑/↓ and
// Enter come from combobox-nav; Tab completes an operator; Enter with nothing
// chosen, or "Search all", posts the text to the search page.
export default class extends Controller {
  static targets = ["input", "list", "pop", "dialog", "revision", "searchAll", "openOptions"]
  static values = { debounce: { type: Number, default: 300 }, palette: Boolean }

  connect() {
    this.combobox = new Combobox(this.inputTarget, this.listTarget, { tabInsertsSuggestions: false })
    this.forget = () => this.clearAll()
    document.addEventListener("turbo:before-cache", this.forget)
    this.guardStale = (event) => this.guard(event)
    this.listTarget.addEventListener("turbo:before-frame-render", this.guardStale)
    this.outside = (event) => {
      if (!this.paletteValue && !this.element.contains(event.target)) this.hide()
    }
    document.addEventListener("click", this.outside)
  }

  disconnect() {
    clearTimeout(this.timer)
    this.combobox.destroy()
    this.listTarget.removeEventListener("turbo:before-frame-render", this.guardStale)
    document.removeEventListener("click", this.outside)
    document.removeEventListener("turbo:before-cache", this.forget)
  }

  // Every keystroke makes the shown suggestions stale: they stop answering
  // keys and clicks until the answer for the new text arrives.
  typed() {
    this.bump()
    this.combobox.stop()
    this.listTarget.setAttribute("data-querylane-stale", "")
    clearTimeout(this.timer)
    if (this.composing) return
    if (this.inputTarget.value.trim() === "") return this.hide()
    this.timer = setTimeout(() => this.inputTarget.form.requestSubmit(), this.debounceValue)
  }

  compose() {
    this.composing = true
    clearTimeout(this.timer)
  }

  composed() {
    this.composing = false
    this.typed()
  }

  submitted() {
    clearTimeout(this.timer)
  }

  keys(event) {
    if (event.key === "Tab" && !event.shiftKey && this.visible) {
      // While the next answer loads, Tab waits rather than leaving the box.
      if (this.listTarget.hasAttribute("data-querylane-stale")) return event.preventDefault()
      const option = this.listTarget.querySelector('[aria-selected="true"][data-querylane-complete]') ||
        this.listTarget.querySelector("[data-querylane-complete]")
      if (!option) return
      event.preventDefault()
      this.complete(option.dataset.querylaneComplete)
    } else if (event.key === "Enter" && (this.listTarget.hasAttribute("data-querylane-stale") || !this.listTarget.querySelector('[aria-selected="true"]'))) {
      event.preventDefault()
      this.go("search")
    } else if (event.key === "Escape" && !this.paletteValue) {
      if (this.visible) this.hide()
      else this.inputTarget.blur()
    }
  }

  // combobox-nav: an option was chosen (Enter or click). Stale options do nothing.
  commit(event) {
    if (this.listTarget.hasAttribute("data-querylane-stale")) return
    const option = event.target.closest('[role="option"]')
    if (!option) return
    if (option.dataset.querylaneComplete) return this.complete(option.dataset.querylaneComplete)
    if (option.dataset.querylaneGo) return this.go(option.dataset.querylaneGo)
    const open = option.querySelector("[data-querylane-open]")
    open ? open.click() : this.go("search")
  }

  // "/" focuses the header box (unless the page has its own box); ⌘K / Ctrl-K opens the palette.
  shortcut(event) {
    if (this.paletteValue) {
      if (event.key.toLowerCase() === "k" && (event.metaKey || event.ctrlKey)) {
        event.preventDefault()
        this.open()
      }
      return
    }
    if (event.key !== "/" || event.metaKey || event.ctrlKey || event.altKey) return
    if (event.target.closest("input, textarea, select, [contenteditable]")) return
    if (document.querySelector(".ql-box-input")) return
    event.preventDefault()
    this.inputTarget.focus()
  }

  open() {
    this.dialogTarget.showModal()
    this.inputTarget.focus()
  }

  closed() {
    this.hide()
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.dialogTarget.close()
  }

  // Focus shows the last list again; a stale one stays inert until its answer renders.
  reopen() {
    if (this.listTarget.childElementCount === 0 || this.inputTarget.value.trim() === "") return
    if (this.listTarget.hasAttribute("data-querylane-stale")) this.popTarget.hidden = false
    else this.show()
  }

  // private

  get visible() {
    return !this.popTarget.hidden
  }

  get revision() {
    return Number(this.revisionTarget.value)
  }

  bump() {
    this.revisionTarget.value = String(this.revision + 1)
  }

  // Replaces the last word; the shown completions no longer apply, so they go
  // until the next answer arrives (a quick Enter cannot pick a stale one).
  complete(word) {
    this.listTarget.querySelectorAll("[data-querylane-complete]").forEach((option) => option.remove())
    const value = this.inputTarget.value.replace(/\S*$/, word)
    this.inputTarget.value = word.endsWith(":") ? value : `${value} `
    this.inputTarget.focus()
    this.typed()
  }

  go(where) {
    clearTimeout(this.timer)
    const button = where === "options" ? this.openOptionsTarget : this.searchAllTarget
    this.inputTarget.form.requestSubmit(button)
  }

  show() {
    if (this.inputTarget.value.trim() === "") return
    this.listTarget.removeAttribute("data-querylane-stale")
    this.popTarget.hidden = false
    this.combobox.start()
  }

  // Before Turbo snapshots the page: nothing typed or suggested is kept.
  clearAll() {
    clearTimeout(this.timer)
    this.bump()
    this.inputTarget.value = ""
    this.inputTarget.removeAttribute("value")
    this.listTarget.innerHTML = ""
    this.hide()
    if (this.paletteValue && this.dialogTarget.open) this.dialogTarget.close()
  }

  hide() {
    this.popTarget.hidden = true
    this.combobox.stop()
  }

  guard(event) {
    if (event.target !== this.listTarget) return
    const answered = Number(event.detail.newFrame?.dataset?.revision)
    if (!Number.isFinite(answered)) return
    const render = event.detail.render
    event.detail.render = (current, next) => {
      if (answered < this.revision) return
      render(current, next)
      this.show()
    }
  }
}
