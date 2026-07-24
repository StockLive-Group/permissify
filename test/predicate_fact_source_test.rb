# frozen_string_literal: true

require "test_helper"
require "permissify/predicate"

# The Predicate adapter is tested against Predicate's *contract* — an object
# responding to call(fact_name, state_hash) -> boolean — with a faithful stub, so
# the suite runs whether or not the `predicate` gem is installed ("with and without
# Predicate"). The stub mirrors exactly what Predicate.for(:entity) returns.
class PredicateFactSourceTest < Minitest::Test
  # Faithful stand-in for Predicate.for(:article): call(name, state) -> boolean.
  class StubEntity
    def initialize(&impl) = (@impl = impl)
    def call(name, state) = @impl.call(name, state)
  end

  Article = Struct.new(:title, :body, :media_ids, :user_id)

  def setup
    Permissify.reset!
  end

  def complete_source
    entity = StubEntity.new do |name, state|
      raise "unexpected fact #{name}" unless name == :content_complete

      !state[:title].to_s.empty? && !state[:body].to_s.empty? && state[:media_ids].any?
    end
    Permissify::PredicateFactSource.new(
      entity: entity,
      facts: [:content_complete],
      state: ->(ctx) { { title: ctx.resource.title, body: ctx.resource.body, media_ids: ctx.resource.media_ids } }
    )
  end

  # --- the port contract ----------------------------------------------------

  def test_owned_fact_returns_boolean_from_the_entity
    ctx = Struct.new(:resource).new(Article.new("t", "b", [1], 7))
    assert_equal true, complete_source.fetch(:content_complete, ctx)

    ctx_incomplete = Struct.new(:resource).new(Article.new("t", "", [], 7))
    assert_equal false, complete_source.fetch(:content_complete, ctx_incomplete)
  end

  def test_unowned_fact_returns_missing_so_other_sources_win
    ctx = Struct.new(:resource).new(Article.new("t", "b", [1], 7))
    assert_same Permissify::FactSource::Missing, complete_source.fetch(:owner, ctx)
  end

  # --- integration with decide ----------------------------------------------

  # The domain fact (:complete) is sourced from Predicate; the volatile authz fact
  # (:owner) stays inline and fresh. This is the intended split.
  def test_decide_composes_a_predicate_domain_fact_with_an_inline_authz_fact
    Permissify.define(:article) do
      fact(:owner) { |ctx| ctx.resource.user_id == ctx.actor[:id] }
      permission(:publishable) { |ctx| ctx.all?(:owner, :content_complete) }
      action :publish, maps_to: :publishable
    end

    owner_complete = Article.new("t", "b", [1], 7)
    decision = Permissify.decide(actor: { id: 7 }, action: :publish, resource: owner_complete,
                                 resource_key: :article, fact_source: complete_source)
    assert decision.allowed?

    owner_incomplete = Article.new("t", "", [], 7)
    denied = Permissify.decide(actor: { id: 7 }, action: :publish, resource: owner_incomplete,
                               resource_key: :article, fact_source: complete_source)
    refute denied.allowed?
    assert_equal :denied, denied.reason
  end

  # Parity: sourcing :complete from Predicate must give the SAME decision as defining
  # it inline with equivalent logic.
  def test_parity_between_sourced_and_inline_domain_fact
    inline = lambda do
      Permissify.reset!
      Permissify.define(:article) do
        fact(:owner)            { |ctx| ctx.resource.user_id == ctx.actor[:id] }
        fact(:content_complete) { |ctx| !ctx.resource.title.to_s.empty? && !ctx.resource.body.to_s.empty? && ctx.resource.media_ids.any? }
        permission(:publishable) { |ctx| ctx.all?(:owner, :content_complete) }
        action :publish, maps_to: :publishable
      end
    end
    sourced = lambda do
      Permissify.reset!
      Permissify.define(:article) do
        fact(:owner) { |ctx| ctx.resource.user_id == ctx.actor[:id] }
        permission(:publishable) { |ctx| ctx.all?(:owner, :content_complete) }
        action :publish, maps_to: :publishable
      end
    end

    [Article.new("t", "b", [1], 7), Article.new("t", "", [], 7), Article.new("t", "b", [1], 9)].each do |article|
      inline.call
      a = Permissify.decide(actor: { id: 7 }, action: :publish, resource: article, resource_key: :article)
      sourced.call
      b = Permissify.decide(actor: { id: 7 }, action: :publish, resource: article, resource_key: :article,
                            fact_source: complete_source)
      assert_equal a.allowed?, b.allowed?, "parity broken for #{article}"
    end
  end

  # An owned fact whose entity raises denies observably with :fact_error — it never
  # leaks through as an allow.
  def test_entity_error_on_owned_fact_denies_with_fact_error
    boom = Permissify::PredicateFactSource.new(
      entity: StubEntity.new { |_n, _s| raise "predicate blew up" },
      facts: [:complete],
      state: ->(_ctx) { {} }
    )
    Permissify.define(:article) do
      permission(:publishable) { |ctx| ctx.all?(:complete) }
      action :publish, maps_to: :publishable
    end
    decision = Permissify.decide(actor: { id: 7 }, action: :publish, resource: Article.new("t", "b", [1], 7),
                                 resource_key: :article, fact_source: boom)
    refute decision.allowed?
    assert_equal :fact_error, decision.reason
  end

  # "Without Predicate": if the domain fact is neither inline nor owned by any source,
  # it denies with :missing_fact — never a silent allow.
  def test_missing_domain_fact_denies_with_missing_fact
    Permissify.define(:article) do
      permission(:publishable) { |ctx| ctx.all?(:complete) }
      action :publish, maps_to: :publishable
    end
    empty = Permissify::PredicateFactSource.new(entity: StubEntity.new { |_n, _s| true }, facts: [], state: ->(_c) { {} })
    decision = Permissify.decide(actor: { id: 7 }, action: :publish, resource: Article.new("t", "b", [1], 7),
                                 resource_key: :article, fact_source: empty)
    refute decision.allowed?
    assert_equal :missing_fact, decision.reason
  end
end
