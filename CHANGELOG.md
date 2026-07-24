# Changelog

## [Unreleased]

### 0.5.0 — zero-config Rails Railtie

- `Permissify::Railtie` — loaded automatically when Rails is present (a conditional
  require in `lib/permissify.rb`, so pure-Ruby hosts keep their stdlib-only footprint).
  It removes all host loader glue:
  - definitions live in `app/permissify/*.rb` (each calls `Permissify.define`);
  - the directory is ignored by Zeitwerk (files register, they don't define constants);
  - definitions register on boot and re-register on every reload via `to_prepare`;
  - `permissify/rails` (the controller concern) is required automatically.
  No initializer is needed. Mirrors the Predicate gem's Railtie so both load identically.

### 0.4.0 — optional Predicate fact source

- `require "permissify/predicate"` → `Permissify::PredicateFactSource` — sources a
  family of stable domain-validity facts from a Predicate entity through the
  `FactSource` port, with no load-time dependency on the `predicate` gem (the entity
  is injected). `facts:` declares the owned names; anything else returns `Missing` so
  inline facts and other sources still win; an owned fact whose entity raises denies
  observably with `:fact_error`.
- Documents the split loudly: Predicate is a memoized *domain* layer beneath
  authorization — for stable facts only, never for volatile roles/ownership.
- Contract tests run with and without Predicate (a faithful `call(name, state)` stub),
  including sourced-vs-inline parity.

### 0.3.0 — optional Rails adapter

- `require "permissify/rails"` + `include Permissify::Controller` — an optional,
  dependency-free controller concern:
  - `permissify_authorize(resource, action:, resource_key:, environment:)` — raises
    `NotAuthorized` on deny, returns the resource on allow.
  - `permissify_scope(relation, …)` — delegates to `authorized_scope` (DB-level).
  - `verify_permissify_authorized` / `verify_permissify_scoped` — after_action guards
    that fail loud when an action forgot to authorize or scope.
  - `permissify_actor` (defaults to `current_user`) and `permissify_environment` are
    overridable; `permissify_resource_key` infers the registry key from the model name.
  - Names are distinct from Pundit's so both can run side by side during a shadow migration.
- Adapter tests run without booting Rails (a fake controller supplies the contract).

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
