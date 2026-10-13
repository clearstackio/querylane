# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "dummy/config/environment"
require "spec_helper"
require "rspec/rails"

RSpec.configure do |config|
  config.before { DummySearch.configure! }
end
