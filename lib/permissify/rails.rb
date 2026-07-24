# frozen_string_literal: true

require_relative "../permissify"

module Permissify
  # Optional Rails integration. It adds nothing to the core and imposes no runtime
  # dependency — `require "permissify/rails"` only when a Rails app wants it, then:
  #
  #   class ApplicationController < ActionController::Base
  #     include Permissify::Controller
  #     verify_permissify_authorized   # fail loud if an action forgot to authorize
  #   end
  #
  #   class ContactsController < ApplicationController
  #     def show
  #       @contact = permissify_authorize(Contact.find(params[:id]))   # raises on deny
  #     end
  #
  #     def index
  #       @contacts = permissify_scope(Contact.all)                    # DB-level narrowing
  #     end
  #   end
  #
  # The names are deliberately distinct from Pundit's (`authorize`, `policy_scope`,
  # `verify_authorized`) so both can run side by side during a shadow migration —
  # see the Pundit-eradication plan.
  module Controller
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # Fail loud (after_action) if an action returned without calling
      # permissify_authorize. A forgotten authorization must never pass silently.
      def verify_permissify_authorized(**options)
        after_action(:permissify_verify_authorized!, **options)
      end

      # Fail loud if an action returned without calling permissify_scope.
      def verify_permissify_scoped(**options)
        after_action(:permissify_verify_scoped!, **options)
      end
    end

    # The subject under authorization. Defaults to +current_user+; override to
    # authorize something else (an API token, an org membership, …).
    def permissify_actor
      current_user
    end

    # Request/tenant context passed to facts as +environment+. Override to supply
    # tenant ids, feature flags, request metadata, etc. Defaults to empty.
    def permissify_environment
      {}
    end

    # Enforce authorization for +resource+. Returns +resource+ on allow so it can
    # wrap an assignment; raises Permissify::NotAuthorized on deny (rescue it in the
    # host, e.g. rescue_from Permissify::NotAuthorized).
    #
    # +action+::       defaults to the controller action_name
    # +resource_key+:: defaults to an inferred key (see permissify_resource_key)
    def permissify_authorize(resource, action: action_name, resource_key: nil, environment: nil)
      @_permissify_authorized = true
      Permissify.authorize!(
        actor: permissify_actor,
        action: action.to_sym,
        resource: resource,
        resource_key: resource_key || permissify_resource_key(resource),
        environment: environment || permissify_environment
      )
      resource
    end

    # Narrow +relation+ to what the actor may see, at the database level. Delegates
    # to Permissify.authorized_scope and raises Permissify::NoScope when the resource
    # has no registered scope (it never returns every row by default).
    def permissify_scope(relation, action: action_name, resource_key: nil, environment: nil)
      @_permissify_scoped = true
      Permissify.authorized_scope(
        actor: permissify_actor,
        action: action.to_sym,
        relation: relation,
        resource_key: resource_key || permissify_resource_key(relation),
        environment: environment || permissify_environment
      )
    end

    private

    # Infer the registry key from a record, relation, or class by its model name:
    # Contact => :contact, LivestockType => :livestock_type. Override for custom maps.
    def permissify_resource_key(target)
      name =
        if target.respond_to?(:model_name)            then target.model_name.name
        elsif target.class.respond_to?(:model_name)   then target.class.model_name.name
        elsif target.is_a?(Module)                    then target.name
        else                                               target.class.name
        end
      demodulized = name.to_s.split("::").last
      demodulized.gsub(/([a-z\d])([A-Z])/, '\1_\2').gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').downcase.to_sym
    end

    def permissify_verify_authorized!
      return if @_permissify_authorized

      raise Permissify::Error,
            "#{self.class}##{action_name} returned without calling permissify_authorize"
    end

    def permissify_verify_scoped!
      return if @_permissify_scoped

      raise Permissify::Error,
            "#{self.class}##{action_name} returned without calling permissify_scope"
    end
  end
end
