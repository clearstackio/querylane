import { Controller } from "@hotwired/stimulus"

// The options panel: field edits refresh the server-composed "Writes" line
// (a hidden submit into its own frame, no search); Enter applies; Reset
// empties the fields; Show reveals a masked field; Escape cancels (a plain
// search, panel closed).
export default class extends Controller {
  static targets = ["field", "preview", "cancel", "apply"]
  static values = { debounce: { type: Number, default: 300 } }

  // Opening the panel moves focus to its first field.
  connect() {
    this.fieldTargets[0]?.focus()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  changed(event) {
    if (!this.fieldTargets.includes(event.target)) return
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.previewTarget.form?.requestSubmit(this.previewTarget), this.debounceValue)
  }

  reset() {
    this.fieldTargets.forEach((field) => {
      if (field.type === "checkbox") field.checked = false
      else field.value = ""
    })
    if (this.fieldTargets.length) this.changed({ target: this.fieldTargets[0] })
  }

  reveal(event) {
    const button = event.currentTarget
    const field = document.getElementById(button.getAttribute("aria-controls"))
    const shown = field.classList.toggle("ql-masked") === false
    button.setAttribute("aria-pressed", String(shown))
    button.textContent = shown ? button.dataset.hide : button.dataset.show
  }

  // Enter in a field applies the panel (the form's default button would close it).
  apply(event) {
    if (!this.fieldTargets.includes(event.target)) return
    event.preventDefault()
    clearTimeout(this.timer)
    this.applyTarget.click()
  }

  cancel(event) {
    event.preventDefault()
    this.cancelTarget.click()
  }
}
