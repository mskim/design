module Design
  # Section saves (D3's Page section, D4's Object section) set one field — or
  # one set that must be written together — at a time. `page_field` and
  # `object_field` name the fields being set; the :page_section and
  # :object_section validators check only those, and read what was typed:
  # decimal and integer columns would cast "abc" to 0 or nil silently.
  # Importers, generators and the paper size form never use the contexts, so
  # nothing here touches them.
  module PageSectionFields
    extend ActiveSupport::Concern

    DECIMAL = /\A[+-]?(\d+(\.\d*)?|\.\d+)\z/ # no exponent, no unit
    INTEGER = /\A[+-]?\d+\z/

    # Where the generic messages live. Each section keeps its own copy of
    # them (design.<scope>.errors.*), so one can be reworded without the
    # other. See config/locales/{ko,en}.yml.
    PAGE_SCOPE = "page_section"
    OBJECT_SCOPE = "object_section"

    included do
      attr_accessor :page_field, :object_field
    end

    private

    def page_fields(allowed) = Array(page_field).map(&:to_s) & allowed
    def object_fields_set(allowed) = Array(object_field).map(&:to_s) & allowed

    # The typed value as a BigDecimal, or nil after adding the error: blank →
    # required; anything unparsable (also a value that is neither a String nor
    # Numeric: true, an Array, a Hash) → not_a_number / not_an_integer.
    def typed_number(field, integer: false, scope: PAGE_SCOPE)
      raw = read_attribute_before_type_cast(field)
      text = raw.is_a?(String) ? raw.strip : raw
      return section_error(field, :required, scope: scope) if text.nil? || text == ""
      if text.is_a?(Numeric)
        return text.to_d if !integer || text == text.to_i
      elsif text.is_a?(String) && text.match?(integer ? INTEGER : DECIMAL)
        return text.to_d
      end
      section_error(field, integer ? :not_an_integer : :not_a_number, scope: scope)
    end

    def section_error(field, key, scope: PAGE_SCOPE, **opts)
      errors.add(field, I18n.t("design.#{scope}.errors.#{key}", **opts))
      nil
    end

    # D3's Page section (the scope its callers already use).
    def page_error(field, key, **opts) = section_error(field, key, **opts)
    # D4's Object section.
    def object_error(field, key, **opts) = section_error(field, key, scope: OBJECT_SCOPE, **opts)
  end
end
