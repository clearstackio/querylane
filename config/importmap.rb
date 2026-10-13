# frozen_string_literal: true

# querylane's browser modules for hosts on importmap-rails (Propshaft or
# Sprockets). Querylane::Engine appends this file to the host's
# `config.importmap.paths`, so the host map gains `querylane` (index.js) and
# one pin per module under its own file name, extension included:
#
#   querylane                                   -> querylane/index.js
#   querylane/overlay.js                        -> querylane/overlay.js
#   querylane/controllers/box_controller.js     -> querylane/controllers/box_controller.js
#   ...
#
# The modules import each other by those names, which also resolve under a
# webpack or esbuild `querylane` alias, as an npm package, and in a hand-written
# import map with one `"querylane/": "/querylane/"` prefix entry.
#
# Nothing is preloaded: a page that imports "querylane" fetches the rest, and
# pages without a search box fetch nothing. A host that wants preloading pins
# the same names again with `preload: true`.
#
# The host pins the peers its page shares with querylane:
#
#   pin "@hotwired/stimulus", to: "stimulus.min.js"   # stimulus-rails
#   pin "@github/combobox-nav"
#
# and loads Turbo 8 however it already does (turbo-rails' pin is fine):
# querylane never imports Turbo.
#
# The pins are listed when the map is drawn: after adding a module file, restart
# the server (importmap-rails redraws only when an importmap.rb changes).
pin "querylane", to: "querylane/index.js", preload: false
(Querylane::Engine.javascript_modules - ["querylane/index.js"]).each do |file|
  pin file, to: file, preload: false
end
