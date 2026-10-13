# frozen_string_literal: true

class PersonPresenter < Querylane::Presenter
  def columns = [Column.new(:team, "Team", 120), Column.new(:started, "Started", 100)]

  def subtitle(group) = "•••-#{group.hits.first.document["id_last4"]}"

  def note(group)
    "matched on name" if result.query.present?
  end

  def cells(hit) = [Cell.new(hit.document["team"], :strong), Cell.new(hit.document["started"], :muted)]

  def status(hit)
    (hit.document["status_label"] == "active") ? Badge.new("Active", :success) : Badge.new("Terminated", :neutral)
  end

  def flags(hit) = hit.document["combo"] ? [Badge.new("Combo", :neutral)] : []

  def outcome(hit)
    if hit.document["status_label"] == "terminated"
      return Reason.new(text: "Terminated. Rehire them first.", link_label: "Rehire", link_url: "/rehire", more: ["Combo-billed division."])
    end

    Action.new("Open ▸", view.open_record_path, {id: hit.id, index: hit.index}, :primary)
  end
end
