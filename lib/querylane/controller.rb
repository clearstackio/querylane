# frozen_string_literal: true

module Querylane
  # Include in the host controller that serves a search page.
  #
  #   def search
  #     if querylane_frame?(:member_search, :writes)
  #       return render partial: "querylane/writes", locals: {preview: querylane_preview(MEMBERS), id: "member_search"}
  #     end
  #     @search = querylane_search(MEMBERS, scope: member_search_scope)
  #     render partial: "members/results" if querylane_frame?(:member_search)
  #   end
  module Controller
    # Runs the search for this request. Query text travels by POST only
    # (unless the host opts in) and responses are never cached.
    #
    # @param definition [Querylane::Definition]
    # @param scope [Querylane::Scope] built on the server for the current user
    # @return [Querylane::Result]
    # @param context [Querylane::Context] facts for the definition's hooks
    def querylane_search(definition, scope:, context: Context.new(request: request), params: self.params, config: Querylane.configuration)
      querylane_guard!(params, config)
      Search.new(definition: definition, request: Request.from_params(params, definition: definition, config: config),
        scope: scope, context: context, config: config).call
    end

    # Suggestions for the header box or palette (operators and people);
    # render with the querylane_suggestions helper.
    #
    # @return [Querylane::Result]
    def querylane_suggest(definition, scope:, context: Context.new(request: request), params: self.params, config: Querylane.configuration)
      querylane_guard!(params, config)
      Search.new(definition: definition, request: Request.from_params(params, definition: definition, config: config),
        scope: scope, context: context, config: config).suggest
    end

    # All records of one group ("More records", the preview), from the
    # request's `group` token; render with querylane/related or querylane/preview.
    #
    # @return [Querylane::Result, nil] nil when the request carries no token
    def querylane_related(definition, scope:, context: Context.new(request: request), params: self.params, config: Querylane.configuration)
      return if params[:group].blank?

      querylane_guard!(params, config)
      Search.new(definition: definition, request: Request.from_params(params.except(config.param_name), definition: definition, config: config),
        scope: scope, context: context, config: config).related
    end

    # What the options panel would write, without searching (the panel's
    # "Writes" line). Render it with the querylane/writes partial.
    #
    # @return [Querylane::Preview]
    def querylane_preview(definition, params: self.params, config: Querylane.configuration)
      querylane_guard!(params, config)
      fields = params[:compose]
      fields = fields.respond_to?(:to_unsafe_h) ? fields.to_unsafe_h : fields.to_h
      Preview.for(definition, params[config.param_name], fields, config: config)
    end

    private

    # Query text and panel fields never travel in a URL (unless the host opts
    # in), and no response is cached. Only the URL's own query string is
    # checked: a host may pass a query it restored on the server (e.g. a
    # remembered search) to a GET.
    def querylane_guard!(_params, config)
      url = request.query_parameters
      carries_text = [config.param_name, :compose, :group].any? { |name| url[name.to_s].present? }
      if request.get? && carries_text && !config.allow_get_query
        raise ActionController::BadRequest, "Search queries are sent by POST"
      end

      response.headers["Cache-Control"] = "no-store"
    end

    public

    # @param id [Symbol, String] the widget id given to querylane_form
    # @param part [Symbol] :results, or :writes (the options panel preview)
    # @return [Boolean] whether this request targets that frame of the widget
    def querylane_frame?(id, part = :results)
      request.headers["Turbo-Frame"] == "#{id}-#{part}"
    end
  end
end
