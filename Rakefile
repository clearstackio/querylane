# frozen_string_literal: true

# `rake` is the local check: the suite and StandardRB. `bin/lint` adds
# FracturedJSON.
require "bundler/setup"
require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "standard/rake"

RSpec::Core::RakeTask.new(:spec)
load "lib/tasks/querylane.rake"

task default: %i[spec standard]
