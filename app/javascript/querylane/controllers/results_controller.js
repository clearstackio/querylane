import { Controller } from "@hotwired/stimulus"

// Lives on the results <turbo-frame> (which persists while its contents are
// replaced): ↑/↓ move between records, Enter opens the focused record, Space
// previews its group (the preview follows ↑/↓, Esc closes it), opening a
// group's "more records" loads them once, the focused record survives a frame
// refresh, selects submit the search form.
export default class extends Controller {
  static targets = ["preview", "previewButton"]

  connect() {
    this.focusFirst = () => this.move(0, true)
    this.remember = (event) => {
      if (event.target !== this.element) return
      const focused = this.element.contains(document.activeElement) ? document.activeElement.closest("[data-querylane-record]") : null
      this.focusedKey = focused?.dataset.querylaneRecord
    }
    // A preview answer that arrives after Esc must not reopen it.
    this.guardPreview = (event) => {
      if (event.target !== this.previewTargetOrNull || this.previewGroup) return
      event.detail.render = () => {}
    }
    this.element.addEventListener("turbo:before-frame-render", this.guardPreview)
    this.restore = (event) => {
      if (event.target !== this.element) return
      this.previewGroup = null
      this.restoreFocus()
    }
    this.element.addEventListener("querylane:focus-first", this.focusFirst)
    this.element.addEventListener("turbo:before-frame-render", this.remember)
    this.element.addEventListener("turbo:frame-render", this.restore)
  }

  disconnect() {
    this.element.removeEventListener("querylane:focus-first", this.focusFirst)
    this.element.removeEventListener("turbo:before-frame-render", this.remember)
    this.element.removeEventListener("turbo:frame-render", this.restore)
    this.element.removeEventListener("turbo:before-frame-render", this.guardPreview)
  }

  keys(event) {
    const record = event.target.closest("[data-querylane-record]")
    if (!record) return
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      const next = this.move(this.records.indexOf(record) + (event.key === "ArrowDown" ? 1 : -1))
      if (next && this.previewing) this.showPreview(next)
    } else if (event.key === "Enter" && event.target === record) {
      event.preventDefault()
      record.querySelector("[data-querylane-open]")?.click()
    } else if (event.key === " " && event.target === record) {
      event.preventDefault()
      this.previewing ? this.closePreview() : this.showPreview(record)
    } else if (event.key === "Escape" && this.previewing) {
      event.preventDefault()
      this.closePreview()
    }
  }

  // A group's "more records" <details>: the first open loads them.
  more(event) {
    const details = event.currentTarget
    if (!details.open || details.dataset.loaded) return
    details.dataset.loaded = "true"
    const button = details.querySelector("[data-querylane-more]")
    button?.form?.requestSubmit(button)
  }

  // A facet's "Find…" box: show the loaded values matching it (all of them,
  // not only the first few); empty shows the first few again.
  findValue(event) {
    const text = event.target.value.trim().toLowerCase()
    event.target.closest(".ql-facet").querySelectorAll(".ql-facet-value").forEach((value) => {
      const label = value.querySelector(".ql-facet-label").textContent.toLowerCase()
      value.hidden = text ? !label.includes(text) : value.hasAttribute("data-querylane-beyond")
    })
  }

  // Enter in a field that names its button (data-querylane-enter) clicks it.
  enter(event) {
    event.preventDefault()
    document.getElementById(event.target.dataset.querylaneEnter)?.click()
  }

  closePreview() {
    if (!this.hasPreviewTarget) return
    this.previewTarget.innerHTML = ""
    this.previewGroup = null
    this.element.querySelector("[data-querylane-previewing]")?.removeAttribute("data-querylane-previewing")
    this.element.querySelector(`[data-querylane-record="${CSS.escape(this.previewKey || "")}"]`)?.focus()
    this.previewKey = null
  }

  submitForm(event) {
    if (event.target.matches("select[form]")) event.target.form?.requestSubmit()
  }

  // private

  get records() {
    return Array.from(this.element.querySelectorAll("[data-querylane-record]"))
  }

  get previewTargetOrNull() {
    return this.hasPreviewTarget ? this.previewTarget : null
  }

  get previewing() {
    return Boolean(this.previewGroup)
  }

  move(index, first = false) {
    const records = this.records
    if (records.length === 0) return null
    const target = records[Math.max(0, Math.min(first ? 0 : index, records.length - 1))]
    target.focus()
    return target
  }

  // Loads the record's group into the preview frame (once per group).
  showPreview(record) {
    const group = record.closest("[data-querylane-group]")
    if (!group || !this.hasPreviewButtonTarget) return
    this.element.querySelector("[data-querylane-previewing]")?.removeAttribute("data-querylane-previewing")
    record.setAttribute("data-querylane-previewing", "")
    this.previewKey = record.dataset.querylaneRecord
    if (this.previewGroup === group.dataset.querylaneGroup) return
    this.previewGroup = group.dataset.querylaneGroup
    this.previewButtonTarget.value = this.previewGroup
    this.previewButtonTarget.form?.requestSubmit(this.previewButtonTarget)
  }

  restoreFocus() {
    if (!this.focusedKey) return
    this.element.querySelector(`[data-querylane-record="${CSS.escape(this.focusedKey)}"]`)?.focus()
  }
}
