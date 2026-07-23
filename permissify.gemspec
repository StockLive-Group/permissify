# frozen_string_literal: true

require_relative "lib/permissify/version"

Gem::Specification.new do |spec|
  spec.name        = "permissify"
  spec.version     = Permissify::VERSION
  spec.authors     = ["StockLive"]
  spec.summary     = "Activity-based authorization: one explicit decision, default-deny, no framework required."
  spec.description = <<~DESC
    Permissify answers `actor.can?(:action, resource)` by evaluating small named
    facts and permissions registered at boot, and returns a structured Decision.
    The core depends only on the Ruby standard library; Rails and Predicate are
    optional adapters loaded when their host constants are available.
  DESC
  spec.homepage    = "https://github.com/StockLive-Group/permissify"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files         = Dir["lib/**/*.rb", "README.md", "LICENSE.txt", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.metadata = {
    "homepage_uri"          => spec.homepage,
    "source_code_uri"       => spec.homepage,
    "rubygems_mfa_required" => "true"
  }
end
