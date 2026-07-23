# frozen_string_literal: true

module Permissify
  # The boot-time store of definitions. It holds, per resource key, the named
  # facts, named permissions, and explicit action aliases. The DSL is only a
  # registration script that writes here; the Registry has the authority.
  # Mutation is synchronized and expected only at boot/reload boundaries.
  class Registry
    # One resource's registered facts, permissions, and action aliases.
    class ResourceDefinition
      attr_reader :key, :facts, :permissions, :actions, :scopes

      def initialize(key)
        @key         = key
        @facts       = {}
        @permissions = {}
        @actions     = {}
        @scopes      = {}
      end
    end

    def initialize
      @resources = {}
      @mutex     = Mutex.new
    end

    def define(resource_key, &block)
      raise DefinitionError, "define requires a block" unless block

      key = resource_key.to_sym
      @mutex.synchronize do
        definition = (@resources[key] ||= ResourceDefinition.new(key))
        DSL.new(definition).instance_eval(&block)
      end
      self
    end

    def resource(resource_key)
      return nil unless resource_key

      @resources[resource_key.to_sym]
    end

    def resource_keys = @resources.keys

    def clear
      @mutex.synchronize { @resources.clear }
      self
    end
  end
end
