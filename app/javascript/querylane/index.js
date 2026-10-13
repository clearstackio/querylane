// querylane — Stimulus controllers and a Turbo stream action.
//
//   import { registerControllers } from "querylane"
//   registerControllers(application)   // the host's Stimulus application
//
// Never starts Stimulus or changes Turbo settings; the host owns both. Never
// imports Turbo either: the stream action is handled through a DOM event, so
// it works with whichever Turbo copy the page loaded (turbo-rails' bundle too).
import BoxController from "querylane/controllers/box_controller.js"
import ResultsController from "querylane/controllers/results_controller.js"
import OptionsController from "querylane/controllers/options_controller.js"
import SuggestController from "querylane/controllers/suggest_controller.js"

// Server rewrote the query (facet toggle, chip ×, Clear): set the box text in
// place, only if the box is still at the revision the response answers.
// Replacing `detail.render` is Turbo's documented hook for a custom action.
document.addEventListener("turbo:before-stream-render", (event) => {
  if (event.target.getAttribute("action") !== "querylane_set_query") return

  event.detail.render = (stream) => {
    const detail = { revision: Number(stream.dataset.revision), query: stream.templateContent.textContent }
    stream.targetElements.forEach((box) => box.dispatchEvent(new CustomEvent("querylane:set-query", { detail })))
  }
})

export function registerControllers(application) {
  application.register("querylane--box", BoxController)
  application.register("querylane--results", ResultsController)
  application.register("querylane--options", OptionsController)
  application.register("querylane--suggest", SuggestController)
}

export { BoxController, OptionsController, ResultsController, SuggestController }
