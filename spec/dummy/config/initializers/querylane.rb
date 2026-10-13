# frozen_string_literal: true

# to_prepare: re-run after every code reload so the searcher follows reloaded classes.
Rails.application.config.to_prepare { DummySearch.configure! }
