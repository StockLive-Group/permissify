# frozen_string_literal: true

require_relative "../permissify"

module Permissify
  # Optional adapter: source a family of facts from a Predicate entity through the
  # FactSource port, without a load-time dependency on the `predicate` gem.
  #
  # Predicate ALWAYS memoizes, so this belongs to STABLE domain-validity facts —
  # "is this article complete?", "does this lot have media?" — never to volatile
  # authorization facts like roles or ownership, which must stay fresh as inline
  # facts. Predicate is a domain layer *beneath* authorization; Permissify reads its
  # result as a plain boolean and still owns the decision.
  #
  #   source = Permissify::PredicateFactSource.new(
  #     entity: Predicate.for(:article),          # responds to call(name, state) -> bool
  #     facts:  [:content_complete],              # the facts this source owns
  #     state:  ->(ctx) { { title: ctx.resource.title, body: ctx.resource.body,
  #                          media_ids: ctx.resource.media_ids } }
  #   )
  #
  #   Permissify.decide(actor:, action:, resource:, resource_key:, fact_source: source)
  #
  # The entity is injected (never looked up here), so the adapter is fully testable
  # with a stub and works whether or not Predicate is installed.
  class PredicateFactSource
    # +entity+:: any object responding to +call(fact_name, state_hash) -> boolean+
    #            (exactly +Predicate.for(:x)+).
    # +facts+::  the fact names this source owns. A name outside this set returns
    #            FactSource::Missing so inline facts and other sources still win.
    # +state+::  a callable +(context) -> Hash+ building the Predicate state from the
    #            DecisionContext (reads +context.resource+, +context.actor+, …).
    def initialize(entity:, facts:, state:)
      @entity = entity
      @facts  = Array(facts).map(&:to_sym)
      @state  = state
    end

    # Return the boolean for an owned fact, or FactSource::Missing for anything else.
    # An error raised by the entity for an owned fact propagates — the decision
    # pipeline converts it into a default-deny with reason :fact_error.
    def fetch(name, context)
      key = name.to_sym
      return FactSource::Missing unless @facts.include?(key)

      @entity.call(key, @state.call(context)) ? true : false
    end
  end
end
