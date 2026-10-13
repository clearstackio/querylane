# frozen_string_literal: true

module Querylane
  # Ships the partials, helper, stylesheet and locale; no routes or models.
  class Engine < ::Rails::Engine
    isolate_namespace Querylane

    initializer "querylane.helper" do
      ActiveSupport.on_load(:action_controller_base) { helper Querylane::SearchHelper }
    end

    initializer "querylane.filter_parameters" do |app|
      # The query and the options panel's fields (which may hold member IDs).
      app.config.filter_parameters |= [Querylane.configuration.param_name, :compose]
    end

    # The gem's browser modules as asset logical paths, e.g.
    # "querylane/controllers/box_controller.js". config/importmap.rb pins them
    # and Sprockets importmap hosts precompile them.
    #
    # @return [Array<String>]
    def self.javascript_modules
      Dir.glob("querylane/**/*.js", base: root.join("app/javascript").to_s).sort
    end

    # Whether the host draws an import map with importmap-rails. A host that
    # only has the constant (another gem loaded it) bundles its own JavaScript.
    #
    # @param app [Rails::Application]
    # @return [Boolean]
    def self.importmap_host?(app)
      defined?(::Importmap) && app.config.respond_to?(:importmap) && app.root.join("config/importmap.rb").exist?
    end

    # Stylesheet on the host's asset pipeline; the ES modules too, for import
    # map hosts only. Sprockets needs precompile entries; Propshaft serves
    # every file on its paths and has no `precompile` setting (OrderedOptions
    # answers respond_to? for any key, so the guard names Sprockets itself).
    initializer "querylane.assets" do |app|
      next unless app.config.respond_to?(:assets)

      sprockets = defined?(::Sprockets::Railtie)
      app.config.assets.precompile += %w[querylane.css] if sprockets
      next unless Engine.importmap_host?(app)

      app.config.assets.paths << root.join("app/javascript").to_s
      # Named files, not a proc: host asset helpers expect plain names.
      app.config.assets.precompile += Engine.javascript_modules if sprockets
    end

    # Import map hosts get the gem's pins (config/importmap.rb) drawn into
    # their own map, and in development a change to the gem's modules sweeps
    # the map's cached digests. Bundler hosts alias `querylane` instead.
    initializer "querylane.importmap", before: "importmap" do |app|
      next unless Engine.importmap_host?(app)

      app.config.importmap.paths << root.join("config/importmap.rb").to_s
      app.config.importmap.cache_sweepers << root.join("app/javascript")
    end
  end
end
