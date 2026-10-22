import { Controller } from "@hotwired/stimulus"
import { paint } from "querylane/overlay.js"

// The search box: a native <input> (the only value) with a decorative overlay
// (operator colours, masked IDs, error underline), debounced submission into
// the results frame, and a revision counter that discards stale responses.
export default class extends Controller {
  static targets = ["input", "overlay", "revision", "box", "hint", "saved", "options"]
  static values = { debounce: { type: Number, default: 300 }, mask: String, frame: String, min: Number }

  connect() {
    this.errorRange = null
    this.frame = document.getElementById(this.frameValue)
    this.guardStaleRenders = (event) => this.guard(event)
    this.readError = () => this.loadError()
    this.frame?.addEventListener("turbo:before-frame-render", this.guardStaleRenders)
    this.frame?.addEventListener("turbo:frame-load", this.readError)
    // The frame's busy attribute (set by Turbo while it loads) shows "Searching…" in the box.
    this.busyObserver = new MutationObserver(() => this.boxTarget.classList.toggle("ql-box-busy", this.frame.hasAttribute("busy")))
    if (this.frame) this.busyObserver.observe(this.frame, { attributes: true, attributeFilter: ["busy"] })
    this.loadError()
    this.paint()
  }

  disconnect() {
    clearTimeout(this.timer)
    this.frame?.removeEventListener("turbo:before-frame-render", this.guardStaleRenders)
    this.frame?.removeEventListener("turbo:frame-load", this.readError)
    this.busyObserver.disconnect()
  }

  // Every keystroke moves the revision, marks chips stale and debounces a submit.
  typed() {
    this.bump()
    this.errorRange = null
    this.frame?.setAttribute("data-querylane-stale", "")
    this.frame?.querySelectorAll("button[name=remove]").forEach((button) => (button.disabled = true))
    this.paint()
    clearTimeout(this.timer)
    if (this.composing) return
    // Too short to search: no request; the last results stay until it is long enough.
    const short = this.tooShort
    if (this.hasHintTarget) this.hintTarget.hidden = !short
    if (short) return
    this.timer = setTimeout(() => this.element.requestSubmit(), this.debounceValue)
  }

  compose() {
    this.composing = true
    clearTimeout(this.timer)
  }

  composed() {
    this.composing = false
    this.typed()
  }

  keys(event) {
    if (event.key === "Enter" && this.tooShort) {
      // Too short to search: Enter keeps the last results and shows the hint.
      event.preventDefault()
      clearTimeout(this.timer)
      if (this.hasHintTarget) this.hintTarget.hidden = false
    } else if (event.key === "Enter") {
      clearTimeout(this.timer)
    } else if (event.key === "Escape" && this.inputTarget.value !== "") {
      event.preventDefault()
      this.clear()
    } else if (event.key === "ArrowDown") {
      event.preventDefault()
      this.frame?.dispatchEvent(new CustomEvent("querylane:focus-first"))
    }
  }

  // "/" anywhere outside a field focuses the box.
  shortcut(event) {
    if (event.key !== "/" || event.metaKey || event.ctrlKey || event.altKey) return
    if (event.target.closest("input, textarea, select, [contenteditable]")) return
    event.preventDefault()
    this.inputTarget.focus()
  }

  clear() {
    this.inputTarget.value = ""
    this.typed()
    this.inputTarget.focus()
  }

  // Toggles, chip ×, Clear and the options panel's Search rewrite the query on the server: send them at a
  // new revision; the rewrite comes back at that same revision.
  submitted(event) {
    clearTimeout(this.timer)
    if (["toggle", "remove", "clear", "compose_submit", "saved", "fix", "instead", "widen", "relax", "as_words"].includes(event.submitter?.name)) this.bump()
  }

  setQuery(event) {
    if (event.detail.revision !== this.revision) return
    this.inputTarget.value = event.detail.query
    const end = this.inputTarget.value.length
    this.inputTarget.setSelectionRange(end, end)
    this.paint()
  }

  // Before Turbo snapshots the page: forget everything a snapshot could keep.
  forget() {
    clearTimeout(this.timer)
    this.bump()
    this.inputTarget.value = ""
    this.inputTarget.defaultValue = ""
    this.inputTarget.removeAttribute("value")
    if (this.frame) this.frame.innerHTML = ""
    this.paint()
  }

  paint() {
    paint(this.overlayTarget, this.inputTarget, { mask: this.maskValue, error: this.errorRange })
  }

  // private

  // Every word shorter than the definition's minimum, and no operator.
  get tooShort() {
    const text = this.inputTarget.value.trim()
    if (!this.minValue || text === "" || text.includes(":")) return false
    return text.split(/\s+/).every((word) => word.replace(/[*"]/g, "").length < this.minValue)
  }

  get revision() {
    return Number(this.revisionTarget.value)
  }

  bump() {
    this.revisionTarget.value = String(this.revision + 1)
  }

  // Drop a response the user has typed past. Wrapping render (instead of
  // preventDefault, which pauses Turbo until resume) keeps later renders flowing;
  // the revision is checked again at the moment of replacement.
  guard(event) {
    if (event.target !== this.frame) return
    const answered = Number(event.detail.newFrame?.dataset?.revision)
    if (!Number.isFinite(answered)) return
    const render = event.detail.render
    event.detail.render = (current, next) => {
      if (answered < this.revision) return
      this.frame.removeAttribute("data-querylane-stale")
      render(current, next)
    }
  }

  // While the options panel is open, Options closes it: a plain search.
  toggleOptions(event) {
    // The panel in the frame is the truth (aria-expanded updates after the frame loads).
    if (!this.frame?.querySelector(".ql-options")) return
    event.preventDefault()
    this.element.requestSubmit()
  }

  // After each answer: the error underline, the Saved star and the Options state.
  loadError() {
    const state = this.frame?.querySelector("[data-querylane-state]")
    if (state && this.hasSavedTarget) this.savedTarget.setAttribute("aria-pressed", state.dataset.savedActive)
    if (state && this.hasOptionsTarget) this.optionsTarget.setAttribute("aria-expanded", state.dataset.optionsOpen)
    const holder = this.frame?.querySelector("[data-querylane-error-range]")
    const range = holder?.dataset.querylaneErrorRange
    this.errorRange = range ? JSON.parse(range) : null
    this.boxTarget.classList.toggle("ql-box-invalid", Boolean(this.errorRange))
    this.paint()
  }
}
