# frozen_string_literal: true

require "rails/railtie"
require_relative "../permissify"
require_relative "rails" # make Permissify::Controller available in Rails apps

module Permissify
  # Optional Rails integration, loaded automatically when Rails is present (see the
  # conditional require at the bottom of lib/permissify.rb). It keeps host setup to
  # zero — no initializer, no loader glue:
  #
  #   * drop definitions in app/permissify/*.rb (each calls Permissify.define)
  #   * they register on boot and re-register on every code reload
  #
  # This mirrors the Predicate gem's Railtie so both frameworks load the same way.
  class Railtie < Rails::Railtie
    DEFINITIONS_DIR = "app/permissify"

    # Definition files call Permissify.define and do NOT define constants matching
    # their paths, so the main Zeitwerk autoloader must ignore the directory.
    initializer "permissify.ignore_definitions", before: :set_autoload_paths do |app|
      path = app.root.join(DEFINITIONS_DIR)
      app.autoloaders.main.ignore(path) if path.exist?
    end

    # Register every definition on boot, and re-register on each reload. `load`
    # (not `require`) so edits are picked up by Rails' reloader in development.
    config.to_prepare do
      Permissify.reset!
      Dir[Rails.root.join(DEFINITIONS_DIR, "**", "*.rb")].sort.each { |file| load file }
    end
  end
end
