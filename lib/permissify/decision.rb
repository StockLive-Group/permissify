# frozen_string_literal: true

module Permissify
  # The immutable result of every evaluation. Boolean helpers (`can?`) are
  # projections of this; enforcement (`authorize!`) reads its reason and checks.
  # It carries only structured, safe identifiers — never arbitrary actor/resource
  # attributes.
  class Decision
    attr_reader :permission, :reason, :checks, :metadata

    # reason is one of:
    #   :allowed :denied :unknown_resource :unknown_action
    #   :unknown_permission :missing_fact :fact_error
    def initialize(allowed:, permission:, reason:, checks: [], metadata: {})
      @allowed    = allowed ? true : false
      @permission = permission
      @reason     = reason
      @checks     = checks.freeze
      @metadata   = metadata.freeze
      freeze
    end

    def allowed? = @allowed
    def denied?  = !@allowed

    def to_h
      { allowed: @allowed, permission: @permission, reason: @reason,
        checks: @checks, metadata: @metadata }
    end
  end
end
