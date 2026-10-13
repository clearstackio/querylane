# frozen_string_literal: true

require_relative "boot"
require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "sprockets/railtie"
require "meilisearch"
require "querylane"

module Dummy
  # A minimal host for querylane's request and browser specs.
  class Application < Rails::Application
    config.load_defaults 8.1
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.hosts.clear
    config.secret_key_base = "querylane-dummy"
    config.action_controller.allow_forgery_protection = false
    config.logger = Logger.new(nil)
    config.action_dispatch.show_exceptions = :rescuable
    config.assets.paths << File.expand_path("../../../app/assets/stylesheets", __dir__)

    gem_root = File.expand_path("../../..", __dir__)
    # ES modules straight from the gem and node_modules (no bundler needed).
    config.middleware.insert_before ActionDispatch::Static, Rack::Static, urls: ["/querylane"], root: File.join(gem_root, "app/javascript"),
      header_rules: [[:all, {"Content-Type" => "text/javascript"}]], cascade: true
    config.middleware.insert_before ActionDispatch::Static, Rack::Static, urls: ["/node_modules"], root: gem_root, cascade: true
  end
end
