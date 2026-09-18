module Design
  # The design editor's Page section (D3). Margins are written on the paper
  # size — every doc type on it — and marked overridden; body line count,
  # column count and gutter on this design. One field per request, or the
  # linked Left/Right pair (values[left_margin_mm], values[right_margin_mm]).
  # Validated in the :page_section context (PageSectionFields) — a failure
  # writes nothing — then the theme .db is re-exported and the answer is turbo
  # streams: a morph of #page-section-content and, unless render_preview=0
  # (more saves are queued), the preview frame (in the print cookie's mode).
  class DocumentDesignPagesController < Design::ApplicationController
    include Design::DocumentDesignPreview

    MARGIN_FIELDS = Design::PaperSize::PAGE_MARGIN_FIELDS
    PAGE_FIELDS = (MARGIN_FIELDS + Design::DocumentDesign::PAGE_DESIGN_FIELDS).freeze
    # Column count and gutter have no "back to": emptying them is a 422.
    REVERTIBLE_FIELDS = (MARGIN_FIELDS + %w[body_line_count]).freeze
    LINKED_FIELDS = %w[left_margin_mm right_margin_mm].freeze

    before_action :set_theme
    before_action :set_paper_size
    before_action :set_document_design
    before_action :ensure_theme_editable
    before_action :set_page_values, only: :update_field
    before_action :ensure_revertible_field, only: :revert_field

    # PATCH page/field (field + value, or values[...] for the linked pair).
    # A blank value for a revertible field is the same as DELETE.
    def update_field
      values = @values.transform_values(&:strip)
      field = values.keys.first
      return revert(field) if values.size == 1 && values[field].empty? && REVERTIBLE_FIELDS.include?(field)

      record = MARGIN_FIELDS.include?(field) ? @paper_size : @document_design
      record.assign_attributes(values)
      record.overridden_fields = record.overridden_fields | values.keys if record.is_a?(Design::PaperSize)
      record.page_field = values.keys
      if record.save(context: :page_section)
        render_saved
      else
        render_invalid(record, values)
      end
    end

    # DELETE page/field (field): a margin back to the rule (unmarked),
    # body_line_count back to the paper size's (nil).
    def revert_field
      revert(params[:field].to_s)
    end

    private

    def set_paper_size
      @paper_size = @theme.paper_sizes.find(params[:paper_size_id])
    end

    # Loaded through @paper_size: the design's paper_size is that same object,
    # so the preview sees a margin written above.
    def set_document_design
      @document_design = @paper_size.document_designs.find(params[:document_design_id])
    end

    def render_preview? = params[:render_preview] != "0"

    def set_page_values
      @values = page_values
      head :bad_request unless @values
    end

    # { field => String }: `field` + `value`, or `values` — the linked pair,
    # left_margin_mm / right_margin_mm keys only. nil (a 400) otherwise.
    def page_values
      if params.key?(:values)
        pair = params[:values]
        return nil unless pair.is_a?(ActionController::Parameters)
        values = pair.to_unsafe_h.to_h
        values if values.any? && (values.keys - LINKED_FIELDS).empty? && values.values.all?(String)
      else
        field = params[:field].to_s
        value = params[:value]
        { field => value } if PAGE_FIELDS.include?(field) && value.is_a?(String)
      end
    end

    def ensure_revertible_field
      head :bad_request unless REVERTIBLE_FIELDS.include?(params[:field].to_s)
    end

    # A margin goes back to the rule through the same :page_section check as
    # a save, so a revert that would newly break a doc type's columns is a 422
    # naming it. The save bumps updated_at: every doc type's preview on the
    # size keys on paper_size.updated_at.
    # body_line_count → nil with update_columns: no validations, so a legacy
    # row failing an unrelated one (cover_type, …) can't make this a 500;
    # updated_at is written for the preview fingerprint.
    def revert(field)
      if MARGIN_FIELDS.include?(field)
        generated = @paper_size.generated_value(field)
        @paper_size.assign_attributes(field => generated, overridden_fields: @paper_size.overridden_fields - [ field ])
        @paper_size.page_field = [ field ]
        return render_invalid(@paper_size, { field => generated.to_s }) unless @paper_size.save(context: :page_section)
      else
        @document_design.update_columns(body_line_count: nil, updated_at: Time.current)
      end
      render_saved
    end

    def render_saved
      Design::ThemeDbExportService.new(@theme).export!
      render turbo_stream: page_streams
    end

    # Nothing was written: reload so the section shows stored values around
    # the attempted ones, with each message under its field.
    def render_invalid(record, values)
      messages = values.keys.index_with { |f| record.errors[f] }.reject { |_, m| m.empty? }
      messages = { values.keys.first => record.errors.full_messages } if messages.empty?
      record.reload
      render turbo_stream: page_streams(field_errors: messages, attempted: values), status: :unprocessable_entity
    end

    # The component is the stream content (render_in: no layout).
    def page_streams(**content)
      component = Design::Views::DocumentDesigns::PageSectionContent.new(
        document_design: @document_design, editable: editable?, **content,
        paper_size_url: helpers.edit_theme_paper_size_path(@theme, @paper_size, return_to: @document_design.id))
      streams = [ turbo_stream.replace(Design::Views::DocumentDesigns::PageSectionContent::TARGET, component, method: :morph) ]
      streams << preview_frame_stream if render_preview?
      streams
    end
  end
end
