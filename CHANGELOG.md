# Changelog

## [Unreleased]

- `EXAMPLES.md` — comprehensive, test-backed examples for every feature.
- RDoc comments across the public API and an `rdoc` Rake task; generated API docs
  build into `doc/` (gitignored) and are published to kuickr, not committed.

### 0.2.0 — authorized scopes + fact-source parity

- `scope(:permission) { |actor, relation, environment| … }` DSL registration.
- `Permissify.authorized_scope(actor:, action:, relation:, resource_key:)` — the
  database-scope port. Delegates to the registered SQL-capable builder and raises
  `NoScope` when none exists (never returns every row by default). Collections are
  never filtered in Ruby as a security boundary.
- FactSource parity test: the same permission yields the same decision whether a
  fact is registered inline or supplied by a `FactSource` (the swap-the-source
  guarantee), plus scope delegation and no-scope tests.

### 0.1.0 — standalone core skeleton

- Ruby-only core, no Rails or Predicate runtime dependency.
- `Permissify.define` DSL: `fact`, `permission`, explicit `action ... maps_to:`.
- `Registry` (boot-time, synchronized) holds facts, permissions, action aliases.
- Typed `DecisionContext` with `fact`, `all?`, `any?`, `none?` and a check trace.
- Immutable structured `Decision` (`allowed`, `permission`, `reason`, `checks`,
  `metadata`).
- `FactSource` port (`fetch` + `Missing` sentinel + `Null` default).
- Safety contracts: default-deny for unknown resource/action/permission/fact;
  evaluation errors deny observably; no superuser bypass; no action fallback.
- `Permissify.decide`, `allow?`, and `authorize!` (raises `NotAuthorized`).
- Minitest suite covering allow/deny, unknown-*, missing-fact, error-denies,
  no-superuser, duplicate-definition.
