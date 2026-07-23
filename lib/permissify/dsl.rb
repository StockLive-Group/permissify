# frozen_string_literal: true

module Permissify
  # Evaluated (via instance_eval) inside `Permissify.define`. Every call writes an
  # immutable entry into a ResourceDefinition. Duplicate names and missing blocks
  # fail loudly at boot; there is no implicit behaviour.
  class DSL
    def initialize(definition)
      @definition = definition
    end

    def fact(name, &block)
      raise DefinitionError, "fact(:#{name}) requires a block" unless block

      key = name.to_sym
      guard_unique!(@definition.facts, key, "fact")
      @definition.facts[key] = block
    end

    def permission(name, &block)
      raise DefinitionError, "permission(:#{name}) requires a block" unless block

      key = name.to_sym
      guard_unique!(@definition.permissions, key, "permission")
      @definition.permissions[key] = block
    end

    # Explicit, finite action aliases. There is no generated ":#{action}able"
    # fallback — an unregistered action denies.
    def action(name, maps_to:)
      key = name.to_sym
      guard_unique!(@definition.actions, key, "action alias")
      @definition.actions[key] = maps_to.to_sym
    end

    # A SQL-capable scope for a permission: a block ->(actor, relation, environment)
    # that returns a narrowed relation. authorized_scope requires one — collections
    # are never filtered in Ruby as a security boundary.
    def scope(permission_name, &block)
      raise DefinitionError, "scope(:#{permission_name}) requires a block" unless block

      key = permission_name.to_sym
      guard_unique!(@definition.scopes, key, "scope")
      @definition.scopes[key] = block
    end

    private

    def guard_unique!(collection, key, kind)
      return unless collection.key?(key)

      raise DefinitionError, "duplicate #{kind} :#{key} on #{@definition.key}"
    end
  end
end
