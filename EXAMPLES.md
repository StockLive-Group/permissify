# Permissify — Comprehensive Examples

Concrete, runnable examples for every feature of Permissify. Each example maps to
behavior covered by the automated tests in `test/` — `test/permissify_test.rb` and
`test/scope_and_fact_source_test.rb`.

Permissify answers one question — *can this **actor** perform this **action** on this
**resource**?* — and returns one explicit, observable `Decision`. It is default-deny,
has no superuser bypass, no generated `":#{action}able"` fallback, and needs no
framework.

## Table of Contents

1. [Defining a resource](#1-defining-a-resource)
2. [Making a decision](#2-making-a-decision)
3. [The Decision object](#3-the-decision-object)
4. [Boolean projection — `allow?`](#4-boolean-projection--allow)
5. [Enforcement — `authorize!`](#5-enforcement--authorize)
6. [Combinators — `all?` / `any?` / `none?`](#6-combinators--all--any--none)
7. [Environment](#7-environment)
8. [Authorized scopes — authorization as a query](#8-authorized-scopes--authorization-as-a-query)
9. [The FactSource port](#9-the-factsource-port)
10. [Safety contracts](#10-safety-contracts)

---

## Real-World Use Cases

11. [Migrating a Pundit policy](#11-migrating-a-pundit-policy)
12. [Optional Predicate as a domain-fact source](#12-optional-predicate-as-a-domain-fact-source)
13. [Rails integration](#13-rails-integration)
14. [Sourcing many domain facts — `PredicateFactSource`](#14-sourcing-many-domain-facts--predicatefactsource)

---

## 1. Defining a resource

A resource is a bundle of named **facts**, **permissions** that compose those facts,
and **actions** that alias to a permission. The DSL is evaluated at boot.

```ruby
Permissify.define(:article) do
  fact(:draft) { |ctx| ctx.resource.status == "draft" }
  fact(:owned) { |ctx| ctx.resource.user_id == ctx.actor.id }

  permission(:editable) { |ctx| ctx.all?(:draft, :owned) }

  action :edit,   maps_to: :editable
  action :update, maps_to: :editable
end
```

- `fact` blocks receive a `DecisionContext` and return a boolean.
- `permission` blocks receive the same context and read facts via combinators.
- `action ..., maps_to:` is the **only** way an action resolves to a permission —
  there is no implicit `":#{action}able"` naming convention.
- Duplicate fact / permission / action / scope names raise `Permissify::DefinitionError`
  at definition time.

---

## 2. Making a decision

```ruby
article  = Struct.new(:status, :user_id).new("draft", 7)
author   = Struct.new(:id).new(7)
stranger = Struct.new(:id).new(9)

Permissify.decide(actor: author,   action: :edit, resource: article, resource_key: :article).allowed?
# => true

Permissify.decide(actor: stranger, action: :edit, resource: article, resource_key: :article).allowed?
# => false  (owned is false)
```

`resource_key` selects the definition; `resource` is the row/object under test;
`action` is the verb. All four are required keywords.

---

## 3. The Decision object

`decide` always returns an immutable `Permissify::Decision` — never a bare boolean,
never `nil`.

```ruby
decision = Permissify.decide(actor: author, action: :edit, resource: article, resource_key: :article)

decision.allowed?    # => true
decision.denied?     # => false
decision.permission  # => :editable
decision.reason      # => :allowed        (or :denied, :unknown_action, :missing_fact, …)
decision.checks      # => [[:all?, [:draft, :owned], true]]   trace of combinator calls
decision.metadata    # => { resource_key: :article, action: :edit }

decision.to_h
# => { allowed: true, permission: :editable, reason: :allowed,
#      checks: [...], metadata: { resource_key: :article, action: :edit } }
```

The `reason` distinguishes an ordinary policy `:denied` from a structural denial
(`:unknown_resource`, `:unknown_action`, `:unknown_permission`, `:missing_fact`,
`:fact_error`) — so a "no" is always explainable.

---

## 4. Boolean projection — `allow?`

When you only need the yes/no:

```ruby
Permissify.allow?(actor: author, action: :edit, resource: article, resource_key: :article)
# => true
```

`allow?` is exactly `decide(...).allowed?` — same arguments, same safety contract.

---

## 5. Enforcement — `authorize!`

At an enforcement boundary, raise on deny. The `Decision` is attached to the error.

```ruby
begin
  Permissify.authorize!(actor: stranger, action: :edit, resource: article, resource_key: :article)
rescue Permissify::NotAuthorized => e
  e.decision.reason      # => :denied
  e.decision.permission  # => :editable
end
```

On allow, `authorize!` returns the `Decision`.

---

## 6. Combinators — `all?` / `any?` / `none?`

Inside a permission, read facts through combinators. Each call is recorded in
`decision.checks`.

```ruby
Permissify.define(:document) do
  fact(:published) { |ctx| ctx.resource.published }
  fact(:owner)     { |ctx| ctx.resource.owner_id == ctx.actor.id }
  fact(:locked)    { |ctx| ctx.resource.locked }

  permission(:viewable)  { |ctx| ctx.any?(:published, :owner) }
  permission(:editable)  { |ctx| ctx.all?(:owner) && ctx.none?(:locked) }

  action :show, maps_to: :viewable
  action :edit, maps_to: :editable
end
```

- `all?(*facts)` — true when every fact is true.
- `any?(*facts)` — true when at least one is true.
- `none?(*facts)` — true when every fact is false.

Facts are memoized per decision, so referencing the same fact twice evaluates it once.

---

## 7. Environment

Pass request- or tenant-scoped context that facts can read, without stuffing it onto
the actor or resource.

```ruby
Permissify.define(:report) do
  fact(:same_tenant) { |ctx| ctx.resource.tenant_id == ctx.environment[:tenant_id] }
  permission(:viewable) { |ctx| ctx.all?(:same_tenant) }
  action :show, maps_to: :viewable
end

Permissify.decide(actor: user, action: :show, resource: report,
                  resource_key: :report, environment: { tenant_id: 42 })
```

---

## 8. Authorized scopes — authorization as a query

For collections, never filter in Ruby. Register a scope builder and let the database
do the narrowing. A missing scope raises `Permissify::NoScope` — it **never** returns
every row by default.

```ruby
Permissify.define(:article) do
  permission(:viewable) { |_ctx| true }
  action :index, maps_to: :viewable

  # builder receives (actor, relation, environment) and returns the narrowed relation
  scope(:viewable) { |actor, relation, _env| relation.where(user_id: actor.id) }
end

Permissify.authorized_scope(actor: current_user, action: :index,
                            relation: Article.all, resource_key: :article)
# => Article.where(user_id: current_user.id)
```

`relation` is anything the host passes — an ActiveRecord relation in a Rails app, or a
plain Array in a test — so the port stays framework-free:

```ruby
rows = [{ id: 1, owner_id: 7 }, { id: 2, owner_id: 9 }, { id: 3, owner_id: 7 }]
Permissify.define(:row) do
  permission(:viewable) { |_| true }
  action :index, maps_to: :viewable
  scope(:viewable) { |actor, relation, _env| relation.select { |r| r[:owner_id] == actor[:id] } }
end

Permissify.authorized_scope(actor: { id: 7 }, action: :index, relation: rows, resource_key: :row)
# => [{ id: 1, owner_id: 7 }, { id: 3, owner_id: 7 }]
```

---

## 9. The FactSource port

Facts don't have to be defined inline. A `FactSource` supplies them externally — and
the **same permission yields the same decision** whether a fact is inline or sourced
(the swap-the-source guarantee).

```ruby
class MyFactSource
  # return the boolean, or FactSource::Missing when this source doesn't know the fact
  def fetch(name, ctx)
    return ctx.resource[:owner_id] == ctx.actor[:id] if name == :owned

    Permissify::FactSource::Missing
  end
end

Permissify.define(:doc) do
  permission(:editable) { |ctx| ctx.all?(:owned) }   # :owned is NOT defined inline
  action :edit, maps_to: :editable
end

Permissify.decide(actor: { id: 7 }, action: :edit, resource: { owner_id: 7 },
                  resource_key: :doc, fact_source: MyFactSource.new).allowed?
# => true
```

The default `FactSource::Null` returns `Missing` for everything; a fact that is neither
inline nor sourced raises `MissingFact`, which denies with reason `:missing_fact`.

---

## 10. Safety contracts

Everything unknown, and every evaluation error, **denies** — observably.

```ruby
# Unknown resource
Permissify.decide(actor: u, action: :edit, resource: r, resource_key: :nope).reason
# => :unknown_resource

# Unknown action (no matching `action ..., maps_to:`)
Permissify.decide(actor: u, action: :teleport, resource: r, resource_key: :article).reason
# => :unknown_action

# A fact that raises does not blow up the request — it denies
Permissify.define(:brittle) do
  fact(:boom) { |_| raise "kaboom" }
  permission(:editable) { |ctx| ctx.all?(:boom) }
  action :edit, maps_to: :editable
end
Permissify.decide(actor: u, action: :edit, resource: r, resource_key: :brittle).reason
# => :fact_error

# No superuser bypass, no ":#{action}able" fallback — an action only resolves through
# an explicit `action ..., maps_to:` mapping.
```

---

## 11. Migrating a Pundit policy

A real StockLive path. Pundit is **data-modelled** — one policy class per record, a
method per controller action, role checks repeated. Permissify is **domain-modelled** —
named facts and permissions, composed once.

```ruby
# BEFORE — Pundit: 14 methods, two repeated role checks
class ContactPolicy < ApplicationPolicy
  def index?   = user.assessor?
  # …9 more, all user.assessor?…
  def destroy? = user.assessor? && user.staff?
  def approve? = user.assessor? && user.staff?
  class Scope < Scope
    def resolve = scope.where(user: user)
  end
end

# AFTER — Permissify: two facts, two permissions, explicit aliases + scope
Permissify.define(:contact) do
  fact(:assessor) { |ctx| ctx.actor.assessor? }
  fact(:staff)    { |ctx| ctx.actor.staff? }

  permission(:viewable)   { |ctx| ctx.all?(:assessor) }
  permission(:manageable) { |ctx| ctx.all?(:assessor, :staff) }

  action :index,   maps_to: :viewable
  action :destroy, maps_to: :manageable
  action :approve, maps_to: :manageable

  scope(:viewable) { |actor, relation, _env| relation.where(user: actor) }
end
```

The 14 repeated `user.assessor?` collapse into one named fact; the `assessor? && staff?`
guards become one `:manageable` permission; the Pundit `Scope` becomes an explicit
`authorized_scope`.

---

## 12. Optional Predicate as a domain-fact source

Permissify needs no other library. But where a **domain-validity** rule already lives in
[Predicate](https://github.com/StockLive-Group/predicate) — stable facts that are safe to
memoize — Permissify can read its result as a plain fact. Authorization stays fresh; the
domain rule stays where it belongs.

```ruby
# Domain layer (Predicate) — "is this article complete?" is a property of the article,
# not of authorization. Memoized because it is stable.
Predicate.define(:article) do
  content_complete { |s| is_present?(s[:title]) && is_present?(s[:body]) && s[:media_ids].any? }
end

# Authorization layer (Permissify) — reads the domain result as one fact
Permissify.define(:article) do
  fact(:complete) do |ctx|
    Predicate.for(:article).call(:content_complete,
      title: ctx.resource.title, body: ctx.resource.body, media_ids: ctx.resource.media_ids)
  end
  fact(:owner) { |ctx| ctx.resource.user_id == ctx.actor.id }

  permission(:publishable) { |ctx| ctx.all?(:owner, :complete) }
  action :publish, maps_to: :publishable
end
```

Predicate is an *optional* domain layer beneath authorization — never a required
dependency, and never the store for volatile authz facts (those stay plain Ruby, and
fresh).

---

## 13. Rails integration

The core needs no framework. In a Rails app, adding the gem is enough — a Railtie loads
automatically (only when Rails is present, so pure-Ruby hosts stay stdlib-only) and gives
you **zero-config** wiring:

- Drop resource definitions in `app/permissify/*.rb` (each calls `Permissify.define`). The
  Railtie ignores that directory in Zeitwerk and registers the files on boot and on every
  reload — **no initializer, no loader glue**.
- `Permissify::Controller` is required for you; just include it.

```ruby
# app/permissify/contact.rb  — registered automatically, no initializer needed
Permissify.define(:contact) do
  fact(:assessor) { |ctx| ctx.actor.assessor? }
  permission(:viewable) { |ctx| ctx.all?(:assessor) }
  action :index, maps_to: :viewable
  scope(:viewable) { |actor, relation, _env| relation.where(user: actor) }
end
```

```ruby
class ApplicationController < ActionController::Base
  include Permissify::Controller
  verify_permissify_authorized          # fail loud if an action forgot to authorize
  rescue_from Permissify::NotAuthorized, with: :forbidden

  private

  def forbidden = head(:forbidden)
end

class ContactsController < ApplicationController
  def show
    @contact = permissify_authorize(Contact.find(params[:id]))   # raises on deny
  end

  def index
    @contacts = permissify_scope(Contact.all)                    # DB-level narrowing
  end
end
```

- `permissify_authorize(resource, action:, resource_key:, environment:)` — returns the
  resource on allow (so it wraps an assignment), raises `NotAuthorized` on deny. `action`
  defaults to the controller `action_name`; `resource_key` is inferred from the model name
  (`Contact` → `:contact`, `LivestockType` → `:livestock_type`) unless given.
- `permissify_scope(relation, …)` — delegates to `authorized_scope`; raises `NoScope` when
  the resource has no registered scope.
- `verify_permissify_authorized` / `verify_permissify_scoped` — after_action guards so a
  forgotten authorization fails loud instead of passing open.
- Override `permissify_actor` (defaults to `current_user`) and `permissify_environment`
  (defaults to `{}`) to change the subject or supply tenant/request context.

The method names are deliberately distinct from Pundit's (`authorize`, `policy_scope`,
`verify_authorized`) so both can run side by side during a shadow migration.

---

## 14. Sourcing many domain facts — `PredicateFactSource`

Section 12 reads a single Predicate result inline. When several **stable domain facts**
come from one Predicate entity, `require "permissify/predicate"` and wire them through the
`FactSource` port instead of writing a block per fact.

```ruby
source = Permissify::PredicateFactSource.new(
  entity: Predicate.for(:article),        # responds to call(name, state) -> boolean
  facts:  [:content_complete, :media_ready],
  state:  ->(ctx) { { title: ctx.resource.title, body: ctx.resource.body,
                      media_ids: ctx.resource.media_ids } }
)

Permissify.define(:article) do
  fact(:owner) { |ctx| ctx.resource.user_id == ctx.actor.id }   # volatile → inline, fresh
  permission(:publishable) { |ctx| ctx.all?(:owner, :content_complete) }
  action :publish, maps_to: :publishable
end

Permissify.decide(actor: user, action: :publish, resource: article,
                  resource_key: :article, fact_source: source)
```

- `facts:` declares exactly which names this source owns; any other name returns `Missing`,
  so inline facts (like `:owner`) and other sources still win.
- An owned fact whose Predicate entity raises denies observably with `:fact_error` — never a
  silent allow. A fact neither inline nor owned denies with `:missing_fact`.
- The entity is injected, so there is **no load-time dependency** on the `predicate` gem;
  the adapter is testable with a stub and degrades safely when Predicate isn't wired.

**Use it only for stable facts.** Predicate always memoizes, so volatile authorization facts
(roles, ownership) must stay inline and fresh — Predicate is a domain layer *beneath*
authorization, never a store for authz state.
