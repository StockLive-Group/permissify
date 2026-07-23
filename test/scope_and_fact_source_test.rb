# frozen_string_literal: true

require "test_helper"

# authorized_scope (the database-scope port) + FactSource parity.
# "relation" is any object the host passes — here a plain Array, so the port is
# provably framework-free.
class ScopeAndFactSourceTest < Minitest::Test
  def setup
    Permissify.reset!
  end

  # --- authorized_scope -----------------------------------------------------

  def test_authorized_scope_delegates_to_registered_builder
    Permissify.define(:article) do
      permission(:viewable) { |_ctx| true }
      action :index, maps_to: :viewable
      scope(:viewable) { |actor, relation, _env| relation.select { |r| r[:owner_id] == actor[:id] } }
    end

    rows = [{ id: 1, owner_id: 7 }, { id: 2, owner_id: 9 }, { id: 3, owner_id: 7 }]
    result = Permissify.authorized_scope(actor: { id: 7 }, action: :index, relation: rows, resource_key: :article)

    assert_equal [{ id: 1, owner_id: 7 }, { id: 3, owner_id: 7 }], result
  end

  def test_authorized_scope_receives_environment
    seen = nil
    Permissify.define(:article) do
      permission(:viewable) { |_ctx| true }
      action :index, maps_to: :viewable
      scope(:viewable) { |_actor, relation, env| seen = env; relation }
    end

    Permissify.authorized_scope(actor: {}, action: :index, relation: [], resource_key: :article,
                                environment: { tenant: 42 })
    assert_equal({ tenant: 42 }, seen)
  end

  def test_authorized_scope_raises_when_no_builder_registered
    Permissify.define(:article) do
      permission(:viewable) { |_ctx| true }
      action :index, maps_to: :viewable
    end

    assert_raises(Permissify::NoScope) do
      Permissify.authorized_scope(actor: {}, action: :index, relation: [], resource_key: :article)
    end
  end

  def test_authorized_scope_raises_on_unknown_resource_or_action
    Permissify.define(:article) { permission(:viewable) { |_| true } }

    assert_raises(Permissify::NoScope) do
      Permissify.authorized_scope(actor: {}, action: :index, relation: [], resource_key: :nope)
    end
    assert_raises(Permissify::NoScope) do
      Permissify.authorized_scope(actor: {}, action: :teleport, relation: [], resource_key: :article)
    end
  end

  def test_duplicate_scope_definition_raises
    assert_raises(Permissify::DefinitionError) do
      Permissify.define(:article) do
        scope(:viewable) { |_a, r, _e| r }
        scope(:viewable) { |_a, r, _e| r }
      end
    end
  end

  # --- FactSource parity ----------------------------------------------------

  # The SAME permission must give the SAME decision whether `owned` is a fact
  # registered inline or supplied by an external FactSource.
  def test_fact_source_parity_with_inline_fact
    source = Object.new
    def source.fetch(name, ctx)
      return ctx.resource[:owner_id] == ctx.actor[:id] if name == :owned

      Permissify::FactSource::Missing
    end

    define_editable = lambda do |inline:|
      Permissify.reset!
      Permissify.define(:doc) do
        fact(:owned) { |ctx| ctx.resource[:owner_id] == ctx.actor[:id] } if inline
        permission(:editable) { |ctx| ctx.all?(:owned) }
        action :edit, maps_to: :editable
      end
    end

    cases = [
      [{ id: 7 }, { owner_id: 7 }, true],
      [{ id: 9 }, { owner_id: 7 }, false]
    ]

    cases.each do |actor, resource, expected|
      define_editable.call(inline: true)
      inline = Permissify.decide(actor: actor, action: :edit, resource: resource, resource_key: :doc)

      define_editable.call(inline: false)
      sourced = Permissify.decide(actor: actor, action: :edit, resource: resource,
                                  resource_key: :doc, fact_source: source)

      assert_equal expected, inline.allowed?, "inline decision mismatch"
      assert_equal inline.allowed?, sourced.allowed?, "fact-source parity broken for #{actor} / #{resource}"
    end
  end
end
