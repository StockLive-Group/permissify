# frozen_string_literal: true

module Permissify
  # The typed input a permission/fact block evaluates against. It is explicit on
  # purpose: it does not serialize the resource, inject magic keys, or hash object
  # graphs. Facts read `actor`, `resource`, and `environment` directly, and compose
  # other facts through `fact`, `all?`, `any?`, `none?`.
  class DecisionContext
    attr_reader :actor, :resource, :action, :environment

    def initialize(actor:, resource:, action:, resource_def:, environment:, fact_source:)
      @actor        = actor
      @resource     = resource
      @action       = action
      @resource_def = resource_def
      @environment  = environment
      @fact_source  = fact_source
      @cache        = {}
      @checks       = []
    end

    # Resolve a named fact to a boolean. Inline-registered facts win; otherwise the
    # FactSource is consulted, and an unresolvable fact raises MissingFact (which
    # the pipeline turns into a default-deny). Results are memoized per context.
    def fact(name)
      key = name.to_sym
      return @cache[key] if @cache.key?(key)

      @cache[key] = compute(key)
    end

    def all?(*names)  = names.all? { |n| record(n) }
    def any?(*names)  = names.any? { |n| record(n) }
    def none?(*names) = names.none? { |n| record(n) }

    # The ordered trace of composed checks, attached to the Decision.
    def checks = @checks

    private

    def record(name)
      result = fact(name)
      @checks << { name: name.to_sym, result: result }
      result
    end

    def compute(name)
      block = @resource_def.facts[name]
      if block
        block.call(self) ? true : false
      else
        value = @fact_source.fetch(name, self)
        raise MissingFact, name if value.equal?(FactSource::Missing)

        value ? true : false
      end
    end
  end
end
