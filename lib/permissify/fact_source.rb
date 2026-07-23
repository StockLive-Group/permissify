# frozen_string_literal: true

module Permissify
  # A FactSource supplies named facts the DSL did not register inline. It responds
  # to `fetch(name, context)` and returns a value, or `FactSource::Missing` when it
  # cannot supply the fact. A missing fact denies the decision — it is never a
  # silent allow. Predicate integration is just an alternative FactSource.
  module FactSource
    # Sentinel meaning "this source cannot answer that fact".
    Missing = Object.new
    def Missing.inspect = "Permissify::FactSource::Missing"
    def Missing.to_s = inspect
    Missing.freeze

    # Default source: answers nothing, so any fact not registered inline denies.
    class Null
      def fetch(_name, _context)
        Missing
      end
    end
  end
end
