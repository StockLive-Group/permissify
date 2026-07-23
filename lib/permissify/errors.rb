# frozen_string_literal: true

module Permissify
  # Base class for every error raised by Permissify.
  class Error < StandardError; end

  # Raised at registration time for an invalid definition (duplicate name,
  # missing block, bad alias).
  class DefinitionError < Error; end

  # Raised internally when a referenced fact cannot be resolved. It is caught by
  # the decision pipeline and converted into a default-deny Decision — it never
  # escapes as a silent allow.
  class MissingFact < Error
    attr_reader :name

    def initialize(name)
      @name = name.to_sym
      super("missing fact: #{@name}")
    end
  end

  # Raised by `authorize!` when a decision denies. The full Decision is attached
  # so callers/rescue handlers can inspect the reason and checks.
  class NotAuthorized < Error
    attr_reader :decision

    def initialize(decision)
      @decision = decision
      super("not authorized: #{decision.permission} (#{decision.reason})")
    end
  end

  # Raised by authorized_scope when no SQL-capable scope builder is registered for
  # the resolved permission. Missing scopes fail loud — never a fallback to all rows.
  class NoScope < Error
    def initialize(resource_key, target)
      super("no authorized_scope registered for #{resource_key}##{target}")
    end
  end
end
