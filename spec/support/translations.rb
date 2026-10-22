# frozen_string_literal: true

# Adds translations for one example. The backend loads its files first, so a
# later lazy load cannot overwrite them; reload after the example to drop them.
module TranslationHelpers
  def store_translations(data)
    I18n.backend.send(:init_translations) unless I18n.backend.initialized?
    I18n.backend.store_translations(:en, data)
  end
end

RSpec.configure do |config|
  config.include TranslationHelpers
end
