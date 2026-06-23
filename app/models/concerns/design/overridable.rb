module Design
  module Overridable
    extend ActiveSupport::Concern

    included do
      attribute :overridden_fields, default: []
    end

    def overridden?(attr) = overridden_fields.include?(attr.to_s)

    def mark_overridden(*attrs)
      hit = attrs.map(&:to_s) - overridden_fields
      return if hit.empty?
      self.overridden_fields = overridden_fields + hit
      save!(validate: false) if persisted?
    end

    # Call AFTER a user-driven update: marks generatable attrs that just changed.
    def mark_overridden_from_changes(generatable)
      mark_overridden(*(generatable.map(&:to_s) & saved_changes.keys))
    end

    private

    # Call in before_create: protect generatable attrs the creator set explicitly.
    def capture_explicit_overrides(generatable)
      self.overridden_fields = overridden_fields | (generatable.map(&:to_s) & changed)
    end
  end
end
