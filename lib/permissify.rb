# frozen_string_literal: true

require_relative "permissify/version"
require_relative "permissify/errors"
require_relative "permissify/fact_source"
require_relative "permissify/decision"
require_relative "permissify/decision_context"
require_relative "permissify/registry"
require_relative "permissify/dsl"

# Permissify — activity-based authorization.
#
#   Permissify.define(:article) do
#     fact(:draft)  { |ctx| ctx.resource.status == "draft" }
#     fact(:owned)  { |ctx| ctx.resource.user_id == ctx.actor.id }
#     permission(:editable) { |ctx| ctx.all?(:draft, :owned) }
#     action :edit, maps_to: :editable
#   end
#
#   decision = Permissify.decide(actor: user, action: :edit,
#                                resource: article, resource_key: :article)
#   decision.allowed?   # => true / false
#
# Safety contract: unknown resource / action / permission / fact and any
# evaluation error all DENY. There is no superuser bypass and no generated
# ":#{action}able" fallback — everything is explicit and observable.
module Permissify
  class << self
    def registry
      @registry ||= Registry.new
    end

    # Reset the global registry — for tests and dev reloads.
    def reset!
      @registry = Registry.new
    end

    # Register a resource's facts, permissions, and action aliases. The block is
    # evaluated by the DSL; see Permissify::DSL for the available declarations.
    def define(resource_key, &block)
      registry.define(resource_key, &block)
    end

    # Evaluate one authorization question and return an immutable Decision.
    #
    # +actor+::        the subject performing the action
    # +action+::       the verb, resolved to a permission via an action alias
    # +resource+::     the object under test
    # +resource_key+:: selects the registered definition
    # +environment+::  optional request/tenant context facts may read
    # +fact_source+::  optional external FactSource for facts not registered inline
    #
    # Unknown resource/action/permission/fact and any evaluation error all DENY,
    # each with a distinct Decision#reason. Never returns a bare boolean or nil.
    def decide(actor:, action:, resource:, resource_key:, environment: {}, fact_source: FactSource::Null.new)
      resource_def = registry.resource(resource_key)
      return deny(:unknown_resource, nil, resource_key: resource_key) unless resource_def

      action_key      = action.to_sym
      permission_name = resource_def.actions[action_key]
      return deny(:unknown_action, nil, resource_key: resource_key, action: action_key) unless permission_name

      permission_block = resource_def.permissions[permission_name]
      return deny(:unknown_permission, permission_name, resource_key: resource_key) unless permission_block

      context = DecisionContext.new(
        actor: actor, resource: resource, action: action_key,
        resource_def: resource_def, environment: environment, fact_source: fact_source
      )

      begin
        allowed = permission_block.call(context) ? true : false
      rescue MissingFact => e
        return deny(:missing_fact, permission_name, checks: context.checks, missing: e.name)
      rescue StandardError => e
        return deny(:fact_error, permission_name, checks: context.checks, error: e.class.name)
      end

      Decision.new(
        allowed: allowed,
        permission: permission_name,
        reason: allowed ? :allowed : :denied,
        checks: context.checks,
        metadata: { resource_key: resource_key, action: action_key }
      )
    end

    # Convenience boolean projection of a decision.
    def allow?(**kwargs)
      decide(**kwargs).allowed?
    end

    # Enforcement: raises NotAuthorized (with the Decision attached) on deny.
    def authorize!(**kwargs)
      decision = decide(**kwargs)
      raise NotAuthorized, decision unless decision.allowed?

      decision
    end

    # Translate authorization into a database query. Delegates to a registered
    # SQL-capable scope builder; raises NoScope if none exists (it never returns
    # every row by default). The builder receives (actor, relation, environment)
    # and returns the narrowed relation.
    def authorized_scope(actor:, action:, relation:, resource_key:, environment: {})
      resource_def = registry.resource(resource_key)
      raise NoScope.new(resource_key, action) unless resource_def

      permission_name = resource_def.actions[action.to_sym]
      raise NoScope.new(resource_key, action) unless permission_name

      builder = resource_def.scopes[permission_name]
      raise NoScope.new(resource_key, permission_name) unless builder

      builder.call(actor, relation, environment)
    end

    private

    def deny(reason, permission, checks: [], **metadata)
      Decision.new(allowed: false, permission: permission, reason: reason,
                   checks: checks, metadata: metadata)
    end
  end
end
