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
    # Filters by whether each attr came from the user (assignment) rather than by
    # dirtiness, so an explicit value equal to the column default is still captured.
    def capture_explicit_overrides(generatable)
      assigned = generatable.map(&:to_s).select { |f| attribute_came_from_user?(f) }
      self.overridden_fields = overridden_fields | assigned
    end

    # Reads the ActiveModel attribute object directly: no public predicate
    # distinguishes "explicitly assigned a value equal to the column default"
    # from "untouched default" — `changed?` can't see the former, but
    # `came_from_user?` (set on assignment) can. That distinction is the whole
    # point of capture (protect authored values even when they equal the default).
    def attribute_came_from_user?(name)
      @attributes[name.to_s].came_from_user?
    end
  end
end
