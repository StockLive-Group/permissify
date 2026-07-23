# Permissify

Activity-based authorization for Ruby. One explicit question, a structured
answer, default-deny by construction. No framework required.

```ruby
Permissify.define(:article) do
  fact(:draft) { |ctx| ctx.resource.status == "draft" }
  fact(:owned) { |ctx| ctx.resource.user_id == ctx.actor.id }

  permission(:editable) { |ctx| ctx.all?(:draft, :owned) }

  action :edit, maps_to: :editable
end

decision = Permissify.decide(actor: user, action: :edit,
                             resource: article, resource_key: :article)
decision.allowed?   # => true / false
decision.reason     # => :allowed / :denied / :unknown_action / :missing_fact / ...
```

## What it guarantees

- **Default-deny.** Unknown resource, action, permission, or fact — and any
  evaluation error — all deny. Nothing is allowed by omission.
- **No superuser bypass.** Elevated access is an ordinary named fact used inside a
  permission, so it is explainable and testable.
- **No magic action fallback.** Action aliases are explicit and finite; there is
  no generated `:"#{action}able"`.
- **Structured decisions.** Every evaluation returns an immutable `Decision`
  (`allowed`, `permission`, `reason`, `checks`, `metadata`). Booleans are
  projections of it.
- **Ruby-only core.** Rails and [Predicate](https://github.com/StockLive-Group/predicate)
  are optional adapters, loaded only when their host constants are present.

## FactSource

Facts a definition does not register inline are resolved through a `FactSource`
(`fetch(name, context)` → value or `FactSource::Missing`). A missing fact denies.
Predicate integration is simply an alternative `FactSource`; swapping it must not
change any decision.

## Status

Early standalone skeleton (`0.1.0`) — the core (Registry, DSL, `DecisionContext`,
`Decision`, `FactSource`, default-deny) is implemented and tested. Rails and
Predicate adapters, and database-level authorized scopes, are next. See the
authoritative contract in the consuming app's `docs/plans/permissify/`.

```bash
bundle install
bundle exec rake test
```
