# frozen_string_literal: true

# The dummy app's saved-search store: in memory, one list for everyone.
module MemorySavedSearches
  Saved = Struct.new(:id, :name, :query, :used_at)

  module_function

  def items = (@items ||= [])

  def reset! = (@items = [])

  def all(context:) = items.sort_by { |saved| saved.used_at || Time.at(0) }.reverse

  def create(context:, name:, query:)
    items << Saved.new((items.size + 1).to_s, name, query, nil)
  end

  def use(context:, id:)
    items.find { |saved| saved.id == id.to_s }&.tap { |saved| saved.used_at = Time.current }
  end
end
