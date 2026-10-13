# frozen_string_literal: true

module Querylane
  # View helpers for a querylane widget. A widget has an id (e.g.
  # :member_search); its form is "#{id}-form", its box "#{id}-box" and its
  # results frame "#{id}-results".
  module SearchHelper
    # The search form with the box. Renders outside the results frame so typing
    # never loses the caret.
    #
    # @param result [Querylane::Result]
    # @param id [Symbol, String] widget id
    # @param url [String] the host endpoint (POST)
    # @param input_id [String] id of the <input> (hosts keep test hooks stable)
    # @param label [String] accessible label of the input
    # @param placeholder [String]
    # @param mask [String, nil] JS regexp source; matching text is shown as dots
    # @param button_id [String, nil] id of the Search button
    # @param options [Boolean] show the Options button (the options panel)
    # @param help [String, nil] help text under the box (the input is described by it)
    # @yield extra controls placed between the clear button and Options
    def querylane_form(result, id:, url:, input_id: "#{id}-query", label: t("querylane.box.label"),
      placeholder: t("querylane.box.placeholder"), mask: nil, button_id: nil, options: true, help: nil, &extra)
      render "querylane/form", result: result, id: id.to_s, url: url, input_id: input_id, label: label,
        placeholder: placeholder, mask: mask, button_id: button_id, options: options, help: help, extra: extra ? capture(&extra) : nil
    end

    # The results frame: chips, state messages, facets, toolbar, the host's rows
    # and the footer.
    #
    # @param result [Querylane::Result]
    # @param id [Symbol, String] widget id
    # @param info_id [String, nil] id of the "Showing x to y of z" line
    # @param per_id [String, nil] id of the page-size select
    # @param first_load [String, nil] HTML shown before anything is typed
    # @param presenter [Class, nil] a Querylane::Presenter subclass; the gem draws the rows
    # @yield instead of a presenter: the host's own rows for result.hits
    def querylane_results(result, id:, presenter: nil, info_id: nil, per_id: nil, first_load: nil, &rows)
      body = if rows
        capture(&rows)
      elsif presenter && result.hits.any?
        render("querylane/rows", presenter: presenter.new(result, self, id: id))
      end
      render "querylane/results", result: result, id: id.to_s, info_id: info_id, per_id: per_id,
        first_load: first_load, rows: body
    end

    # A hit attribute with matched words wrapped in <mark>. The value is
    # escaped first; only querylane's private highlight markers become tags.
    #
    # @return [ActiveSupport::SafeBuffer]
    def querylane_highlight(hit, attribute)
      text = (hit.formatted[attribute.to_s] || hit.document[attribute.to_s]).to_s
      parts = text.split(/(#{Searchers::Meilisearch::HIGHLIGHT_PRE}.*?#{Searchers::Meilisearch::HIGHLIGHT_POST})/o)
      safe_join(parts.map do |part|
        if part.start_with?(Searchers::Meilisearch::HIGHLIGHT_PRE)
          tag.mark(part.delete(Searchers::Meilisearch::HIGHLIGHT_PRE + Searchers::Meilisearch::HIGHLIGHT_POST))
        else
          part
        end
      end)
    end

    # A search box with suggestions for any page: :header (inline dropdown) or
    # :palette (⌘K / Ctrl-K dialog). It posts to `url` for suggestions; Enter
    # and "Search all" post the text to `search_url` (a full page).
    #
    # @param mode [Symbol] :header or :palette
    # @param trigger [Boolean] palette only: show its button (⌘K always opens it)
    def querylane_suggest_box(id:, url:, search_url:, mode: :header, label: t("querylane.suggest.label"),
      placeholder: t("querylane.suggest.placeholder"), trigger: true)
      render "querylane/suggest_box", id: id.to_s, url: url, search_url: search_url, mode: mode, label: label,
        placeholder: placeholder, trigger: trigger
    end

    # The suggestions frame (operators, people, go-to).
    #
    # @param result [Querylane::Result] from querylane_suggest
    # @param presenter [Class] a Querylane::Presenter subclass
    def querylane_suggestions(result, id:, presenter:)
      presenter = presenter.new(result, self, id: id)
      groups = result.hits.any? ? presenter.groups.first(Querylane.configuration.suggest_people) : []
      render "querylane/suggestions", result: result, presenter: presenter, groups: groups, id: id.to_s
    end

    # The response to a group request: the "more records" frame or the preview.
    #
    # @param result [Querylane::Result] from querylane_related
    # @param presenter [Class] a Querylane::Presenter subclass
    # @param frame [String] the requesting frame id (Turbo-Frame header)
    def querylane_related(result, id:, presenter:, frame:)
      presenter = presenter.new(result, self, id: id)
      if frame == "#{id}-preview"
        render "querylane/preview", result: result, presenter: presenter, id: id.to_s
      else
        frame = "#{id}-related-unknown" unless frame.to_s.match?(/\A#{Regexp.escape(id.to_s)}-related-\h{16}\z/)
        render "querylane/related", result: result, presenter: presenter, frame: frame
      end
    end

    # Character range → UTF-16 range, for the browser.
    #
    # @return [Array(Integer, Integer), nil]
    def querylane_utf16_range(text, range)
      return unless range

      start = text[0...range.begin].to_s.encode("UTF-16LE").bytesize / 2
      [start, start + (text[range].to_s.encode("UTF-16LE").bytesize / 2)]
    end
  end
end
