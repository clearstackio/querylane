# frozen_string_literal: true

# The dummy app's saved-search store: in memory, one list for everyone.
module MemorySavedSearches
  Saved = Struct.new(:id, :name, :query, :used_at)

  module_function

  def items = (@items ||= [])

  def reset!
    @items = []
    @next_id = 0
  end

  def all(context:) = items.sort_by { |saved| saved.used_at || Time.at(0) }.reverse

  def create(context:, name:, query:)
    @next_id = (@next_id || 0) + 1
    items << Saved.new(@next_id.to_s, name, query, nil)
  end

  def use(context:, id:)
    items.find { |saved| saved.id == id.to_s }&.tap { |saved| saved.used_at = Time.current }
  end

  # @return [Boolean] whether the reference store held the selected entry
  def delete(context:, id:)
    saved = items.find { |item| item.id == id.to_s }
    saved ? !!items.delete(saved) : false
  end
end
