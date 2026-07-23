# frozen_string_literal: true

require "test_helper"

# Generic, StockLive-free examples — the public gem never references app roles.
# actor/resource are opaque hashes here; facts decide how to read them.
class PermissifyTest < Minitest::Test
  def setup
    Permissify.reset!
    Permissify.define(:article) do
      fact(:draft)       { |ctx| ctx.resource[:status] == "draft" }
      fact(:owned)       { |ctx| ctx.resource[:user_id] == ctx.actor[:id] }
      fact(:actor_admin) { |ctx| ctx.actor[:admin] == true }
      # facts compose other facts:
      fact(:admin)       { |ctx| ctx.fact(:actor_admin) }

      permission(:editable)    { |ctx| ctx.all?(:draft, :owned) }
      permission(:publishable) { |ctx| ctx.all?(:draft, :admin) }

      action :edit,    maps_to: :editable
      action :publish, maps_to: :publishable
    end
  end

  def edit(actor:, resource:, **opts)
    Permissify.decide(actor: actor, action: :edit, resource: resource, resource_key: :article, **opts)
  end

  def test_allows_owner_editing_own_draft
    d = edit(actor: { id: 1 }, resource: { status: "draft", user_id: 1 })
    assert d.allowed?
    assert_equal :editable, d.permission
    assert_equal :allowed, d.reason
  end

  def test_denies_non_owner
    d = edit(actor: { id: 2 }, resource: { status: "draft", user_id: 1 })
    assert d.denied?
    assert_equal :denied, d.reason
  end

  def test_denies_editing_published
    d = edit(actor: { id: 1 }, resource: { status: "published", user_id: 1 })
    assert d.denied?
  end

  def test_composed_fact_publish
    d = Permissify.decide(actor: { id: 9, admin: true }, action: :publish,
                          resource: { status: "draft", user_id: 1 }, resource_key: :article)
    assert d.allowed?, "admin fact composed via :actor_admin should allow publish on a draft"
  end

  def test_no_superuser_bypass
    # admin is NOT a global bypass — :editable requires draft && owned regardless.
    d = edit(actor: { id: 9, admin: true }, resource: { status: "published", user_id: 1 })
    assert d.denied?
  end

  def test_unknown_resource_denies
    d = Permissify.decide(actor: {}, action: :edit, resource: {}, resource_key: :nope)
    assert d.denied?
    assert_equal :unknown_resource, d.reason
  end

  def test_unknown_action_denies_no_fallback
    d = Permissify.decide(actor: { id: 1 }, action: :teleport,
                          resource: { status: "draft", user_id: 1 }, resource_key: :article)
    assert d.denied?
    assert_equal :unknown_action, d.reason
  end

  def test_missing_fact_denies
    Permissify.reset!
    Permissify.define(:widget) do
      permission(:viewable) { |ctx| ctx.all?(:external_flag) } # not registered, no source
      action :view, maps_to: :viewable
    end
    d = Permissify.decide(actor: {}, action: :view, resource: {}, resource_key: :widget)
    assert d.denied?
    assert_equal :missing_fact, d.reason
    assert_equal :external_flag, d.metadata[:missing]
  end

  def test_fact_source_supplies_missing_fact
    Permissify.reset!
    Permissify.define(:widget) do
      permission(:viewable) { |ctx| ctx.all?(:external_flag) }
      action :view, maps_to: :viewable
    end
    source = Object.new
    def source.fetch(name, _ctx)
      name == :external_flag ? true : Permissify::FactSource::Missing
    end
    d = Permissify.decide(actor: {}, action: :view, resource: {}, resource_key: :widget, fact_source: source)
    assert d.allowed?
  end

  def test_evaluation_error_denies_observably
    Permissify.reset!
    Permissify.define(:widget) do
      fact(:boom) { |_ctx| raise "kaboom" }
      permission(:viewable) { |ctx| ctx.all?(:boom) }
      action :view, maps_to: :viewable
    end
    d = Permissify.decide(actor: {}, action: :view, resource: {}, resource_key: :widget)
    assert d.denied?
    assert_equal :fact_error, d.reason
    assert_equal "RuntimeError", d.metadata[:error]
  end

  def test_authorize_bang_raises_with_decision
    err = assert_raises(Permissify::NotAuthorized) do
      Permissify.authorize!(actor: { id: 2 }, action: :edit,
                            resource: { status: "draft", user_id: 1 }, resource_key: :article)
    end
    assert_equal :editable, err.decision.permission
    assert_equal :denied, err.decision.reason
  end

  def test_duplicate_fact_definition_raises
    assert_raises(Permissify::DefinitionError) do
      Permissify.define(:article) { fact(:draft) { |_| true } } # :draft already defined in setup
    end
  end

  def test_decision_is_frozen_and_structured
    d = edit(actor: { id: 1 }, resource: { status: "draft", user_id: 1 })
    assert d.frozen?
    assert_kind_of Array, d.checks
    assert(d.checks.all? { |c| c.key?(:name) && c.key?(:result) })
  end
end
