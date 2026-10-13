# frozen_string_literal: true

require "rails_helper"
require "importmap-rails"

RSpec.describe "querylane import map" do
  let(:javascript_root) { Querylane::Engine.root.join("app/javascript").to_s }
  let(:modules) { Querylane::Engine.javascript_modules }
  let(:map) { Importmap::Map.new.draw(Querylane::Engine.root.join("config/importmap.rb")) }
  # Stands in for the host's asset helpers: logical path to digested URL.
  let(:resolver) { Class.new { def path_to_asset(path) = "/assets/#{path.delete_suffix(".js")}-digest.js" }.new }
  let(:imports) { JSON.parse(map.to_json(resolver: resolver)).fetch("imports") }

  it "lists every module file" do
    expect(modules).to eq(Dir[File.join(javascript_root, "querylane/**/*.js")].map { |file| file.delete_prefix("#{javascript_root}/") }.sort)
    expect(modules).to include("querylane/index.js", "querylane/overlay.js", "querylane/controllers/box_controller.js")
  end

  it "pins querylane and every module under its file name, none preloaded" do
    expect(imports.fetch("querylane")).to eq("/assets/querylane/index-digest.js")
    expect(imports.keys).to match_array(["querylane", *(modules - ["querylane/index.js"])])
    expect(imports.fetch("querylane/controllers/box_controller.js")).to eq("/assets/querylane/controllers/box_controller-digest.js")
    expect(map.preloaded_module_paths(resolver: resolver)).to be_empty
  end

  it "imports its own modules only by pinned names, and never Turbo" do
    # Static, side-effect, re-export and dynamic imports, across lines.
    specifiers = modules.flat_map do |file|
      File.read(File.join(javascript_root, file)).scan(/(?:\bfrom|\bimport)\s*\(?\s*["']([^"']+)["']/).flatten
    end.uniq

    expect(specifiers).to include("@hotwired/stimulus", "querylane/overlay.js")
    expect(specifiers - %w[@github/combobox-nav @hotwired/stimulus]).to all(satisfy { |specifier| imports.key?(specifier) })
  end

  it "exports every module from the npm package" do
    exports = JSON.parse(File.read(File.join(javascript_root, "querylane/package.json"))).fetch("exports")

    expect(exports).to eq("." => "./index.js", "./*" => "./*")
  end

  describe "the engine initializers" do
    let(:host_root) { Pathname.new(Dir.mktmpdir) }
    let(:config) do
      ActiveSupport::OrderedOptions.new.tap do |options|
        options.assets = ActiveSupport::OrderedOptions.new.merge!(paths: [], precompile: [])
        options.importmap = ActiveSupport::OrderedOptions.new.merge!(paths: [], cache_sweepers: [])
      end
    end
    let(:app) { Struct.new(:config, :root).new(config, host_root) }

    after { FileUtils.remove_entry(host_root) }

    def run(name)
      Querylane::Engine.initializers.find { |initializer| initializer.name == name }.bind(Querylane::Engine.instance).run(app)
    end

    context "when the host draws an import map" do
      before do
        host_root.join("config").mkpath
        host_root.join("config/importmap.rb").write("")
      end

      it "adds the map and a cache sweeper, before importmap-rails draws" do
        run("querylane.importmap")

        expect(Querylane::Engine.initializers.find { |initializer| initializer.name == "querylane.importmap" }.before).to eq("importmap")
        expect(config.importmap.paths).to eq([Querylane::Engine.root.join("config/importmap.rb").to_s])
        expect(config.importmap.cache_sweepers).to eq([Querylane::Engine.root.join("app/javascript")])
      end

      it "puts the modules on the asset path and, under Sprockets, precompiles them" do
        run("querylane.assets")

        expect(config.assets.paths).to eq([javascript_root])
        expect(config.assets.precompile).to eq(["querylane.css", *modules])
      end

      it "sets no precompile list under Propshaft" do
        hide_const("Sprockets::Railtie")
        config.assets.delete(:precompile)

        run("querylane.assets")

        expect(config.assets.paths).to eq([javascript_root])
        expect(config.assets.key?(:precompile)).to be(false)
      end
    end

    context "when importmap-rails is loaded but the host bundles its own JavaScript" do
      it "leaves the modules out of the asset pipeline and the map" do
        run("querylane.assets")
        run("querylane.importmap")

        expect(config.assets.paths).to be_empty
        expect(config.assets.precompile).to eq(["querylane.css"])
        expect(config.importmap.paths).to be_empty
        expect(config.importmap.cache_sweepers).to be_empty
      end
    end
  end
end
