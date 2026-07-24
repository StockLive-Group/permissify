# frozen_string_literal: true

require "test_helper"
require "permissify/rails"

# The Rails adapter is exercised without booting Rails: a tiny fake controller
# supplies the only contract Permissify::Controller depends on — current_user,
# action_name, and a class-level after_action hook.
class RailsAdapterTest < Minitest::Test
  Contact = Struct.new(:owner_id)

  # Minimal stand-in for ActionController. Records after_action callbacks so the
  # test can fire them, exactly as Rails would after the action returns.
  class FakeController
    include Permissify::Controller

    class << self
      def after_actions = @after_actions ||= []

      def after_action(name, **_opts)
        after_actions << name
      end
    end

    attr_accessor :current_user, :action_name

    def initialize(user:, action:)
      @current_user = user
      @action_name  = action
    end

    # Run the registered after_action guards, as Rails would.
    def run_after_actions!
      self.class.after_actions.each { |cb| send(cb) }
    end
  end

  def setup
    Permissify.reset!
    Permissify.define(:contact) do
      fact(:owner) { |ctx| ctx.resource.owner_id == ctx.actor[:id] }
      permission(:viewable) { |ctx| ctx.all?(:owner) }
      action :show,  maps_to: :viewable
      action :index, maps_to: :viewable
      scope(:viewable) { |actor, relation, _env| relation.select { |r| r.owner_id == actor[:id] } }
    end
  end

  def controller(action:, user: { id: 7 })
    FakeController.new(user: user, action: action)
  end

  # --- permissify_authorize -------------------------------------------------

  def test_authorize_returns_the_resource_on_allow
    c = controller(action: "show")
    contact = Contact.new(7)
    assert_same contact, c.permissify_authorize(contact)
  end

  def test_authorize_raises_not_authorized_on_deny
    c = controller(action: "show", user: { id: 9 })
    error = assert_raises(Permissify::NotAuthorized) do
      c.permissify_authorize(Contact.new(7))
    end
    assert_equal :denied, error.decision.reason
    assert_equal :viewable, error.decision.permission
  end

  def test_authorize_infers_resource_key_from_model_name
    # A record that exposes a Rails-style model_name maps to its snake_case key.
    livestock = Object.new
    def livestock.model_name = Struct.new(:name).new("LivestockType")
    def livestock.owner_id = 7
    Permissify.define(:livestock_type) do
      permission(:viewable) { |_| true }
      action :show, maps_to: :viewable
    end
    c = controller(action: "show")
    assert c.permissify_authorize(livestock) # no ArgumentError => key inferred as :livestock_type
  end

  def test_authorize_accepts_explicit_action_and_key_and_environment
    seen_env = nil
    Permissify.reset!
    Permissify.define(:contact) do
      fact(:same_tenant) { |ctx| ctx.environment[:tenant] == 1 }
      permission(:viewable) { |ctx| ctx.all?(:same_tenant) }
      action :show, maps_to: :viewable
    end
    c = controller(action: "ignored")
    c.define_singleton_method(:permissify_environment) { { tenant: 1 } }
    assert c.permissify_authorize(Contact.new(7), action: :show, resource_key: :contact)
  end

  # --- permissify_scope -----------------------------------------------------

  def test_scope_narrows_the_relation_at_the_port
    c = controller(action: "index")
    rows = [Contact.new(7), Contact.new(9), Contact.new(7)]
    result = c.permissify_scope(rows, resource_key: :contact)
    assert_equal [Contact.new(7), Contact.new(7)], result
  end

  def test_scope_raises_no_scope_when_unregistered
    Permissify.reset!
    Permissify.define(:contact) do
      permission(:viewable) { |_| true }
      action :index, maps_to: :viewable
    end
    c = controller(action: "index")
    assert_raises(Permissify::NoScope) { c.permissify_scope([], resource_key: :contact) }
  end

  # --- enforcement guards ---------------------------------------------------

  def test_verify_authorized_raises_when_authorize_was_not_called
    FakeController.after_actions.clear
    FakeController.verify_permissify_authorized
    c = controller(action: "show")
    assert_raises(Permissify::Error) { c.run_after_actions! }
  end

  def test_verify_authorized_passes_when_authorize_was_called
    FakeController.after_actions.clear
    FakeController.verify_permissify_authorized
    c = controller(action: "show")
    c.permissify_authorize(Contact.new(7))
    c.run_after_actions! # no raise
  end

  def test_verify_scoped_raises_when_scope_was_not_called
    FakeController.after_actions.clear
    FakeController.verify_permissify_scoped
    c = controller(action: "index")
    assert_raises(Permissify::Error) { c.run_after_actions! }
  end
end
