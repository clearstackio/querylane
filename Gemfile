# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Default searcher (hosts add it themselves).
gem "meilisearch", "~> 0.33.0"

group :development, :test do
  gem "capybara"
  gem "capybara-playwright-driver"
  gem "importmap-rails", require: false # specs draw config/importmap.rb with it
  gem "puma"
  gem "rspec-rails"
  gem "sprockets-rails"
  gem "standard", require: false
end
