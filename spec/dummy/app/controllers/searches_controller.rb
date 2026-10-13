# frozen_string_literal: true

class SearchesController < ActionController::Base
  include Querylane::Controller

  layout "application"

  def show
    @result = querylane_search(DummySearch.definition, scope: scope)
  end

  def search
    if querylane_frame?(:people, :writes)
      return render partial: "querylane/writes", locals: {preview: querylane_preview(DummySearch.definition), id: "people"}
    end

    if (related = querylane_related(DummySearch.definition, scope: scope))
      return render html: helpers.querylane_related(related, id: :people, presenter: PersonPresenter, frame: request.headers["Turbo-Frame"])
    end

    @result = querylane_search(DummySearch.definition, scope: scope)
    if querylane_frame?(:people)
      render partial: "searches/results", locals: {result: @result}
    else
      render :show
    end
  end

  def suggest
    result = querylane_suggest(DummySearch.definition, scope: scope)
    id = %w[find palette].find { |candidate| querylane_frame?(candidate, :list) } || "find"
    render html: helpers.querylane_suggestions(result, id: id, presenter: PersonPresenter)
  end

  # Another page: the header box and the palette.
  def elsewhere
  end

  def open
    render plain: "Opened #{params[:index]} #{params[:id]}"
  end

  private

  # Contractors are visible only on the "ops" team.
  def scope
    Querylane::Scope.new(staff: Querylane::Filter.everything, contractors: Querylane::Filter.eq(:team, "ops"))
  end
end
