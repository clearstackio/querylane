# frozen_string_literal: true

require_relative "lib/querylane/version"

Gem::Specification.new do |spec|
  spec.name = "querylane"
  spec.version = Querylane::VERSION
  spec.authors = ["Ajaya Agrawalla"]
  spec.email = ["ajaya@clearstack.io"]
  spec.summary = "Gmail-style search box, operators, chips and facets for Rails on Hotwire"
  spec.description = "A Rails engine: server-parsed query language, interpretation chips, " \
    "disjunctive facets and keyboard-driven results on Turbo Frames and Stimulus, " \
    "with a Meilisearch searcher."
  spec.homepage = "https://github.com/clearstackio/querylane"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "#{spec.homepage}/tree/master",
    "changelog_uri" => "#{spec.homepage}/blob/master/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "documentation_uri" => "#{spec.homepage}/tree/master/docs/guides",
    "rubygems_mfa_required" => "true",
    "allowed_push_host" => "https://rubygems.org"
  }

  # Files known to git, without the suite, docs, CI and development tooling.
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |file|
      file.start_with?(*%w[bin/ docs/ spec/ .]) ||
        %w[Gemfile Gemfile.lock Rakefile mise.toml package.json package-lock.json AGENTS.md].include?(file) ||
        file == File.basename(__FILE__)
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", "~> 8.1.0"
end
