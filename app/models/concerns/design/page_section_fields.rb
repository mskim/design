module Design
  # Page section saves (D3) set one field — or the linked Left/Right margin
  # pair — at a time. `page_field` names the fields being set; the
  # :page_section validators (PaperSize, DocumentDesign) check only those, and
  # read what was typed: decimal and integer columns would cast "abc" to 0 or
  # nil silently. Importers, generators and the paper size form never use the
  # context, so nothing here touches them.
  module PageSectionFields
    extend ActiveSupport::Concern

    DECIMAL = /\A[+-]?(\d+(\.\d*)?|\.\d+)\z/ # no exponent, no unit
    INTEGER = /\A[+-]?\d+\z/

    included do
      attr_accessor :page_field
    end

    private

    def page_fields(allowed) = Array(page_field).map(&:to_s) & allowed

    # The typed value as a BigDecimal, or nil after adding the error: blank →
    # required; anything unparsable (also a value that is neither a String nor
    # Numeric: true, an Array, a Hash) → not_a_number / not_an_integer.
    def typed_number(field, integer: false)
      raw = read_attribute_before_type_cast(field)
      text = raw.is_a?(String) ? raw.strip : raw
      return page_error(field, :required) if text.nil? || text == ""
      if text.is_a?(Numeric)
        return text.to_d if !integer || text == text.to_i
      elsif text.is_a?(String) && text.match?(integer ? INTEGER : DECIMAL)
        return text.to_d
      end
      page_error(field, integer ? :not_an_integer : :not_a_number)
    end

    def page_error(field, key, **opts)
      errors.add(field, I18n.t("design.page_section.errors.#{key}", **opts))
      nil
    end
  end
end
