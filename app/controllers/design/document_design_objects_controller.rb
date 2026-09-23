module Design
  # The design editor's Object section (D4): the copyright text box and the
  # front wing's author photo, both written on this design only. One field per
  # request, or one whitelisted joint set (values[...]) — a cell size with its
  # partner, typed or dragged — validated and written together in the
  # :object_section context, so a set that doesn't fit the grid writes
  # nothing. Then the theme .db is re-exported and the answer is turbo streams:
  # a morph of #object-section-content and, unless render_preview=0 (more saves
  # are queued), the preview frame (in the print cookie's mode).
  #
  # Which fields exist is the doc type's business (DocumentDesign#object_fields):
  # anything else — a photo field on copyright, any of them on chapter — is a 400.
  class DocumentDesignObjectsController < Design::ApplicationController
    include Design::DocumentDesignPreview

    before_action :set_theme
    before_action :set_paper_size
    before_action :set_document_design
    before_action :ensure_theme_editable
    before_action :set_object_values, only: :update_field
    before_action :ensure_object_field, only: :revert_field

    # PATCH object/field (field + value, or values[...] for the one joint set
    # this doc type has). A blank value is the same as DELETE: every field here
    # has a default.
    def update_field
      values = @values.transform_values(&:strip)
      field = values.keys.first
      return revert(field) if values.size == 1 && values[field].empty?

      @document_design.assign_attributes(values)
      @document_design.object_field = values.keys
      if @document_design.save(context: :object_section)
        render_saved
      else
        render_invalid(values)
      end
    end

    # DELETE object/field (field): back to the default — nil for a text-box
    # field (the engine's 7 / 4 / 6), the column default for a photo field.
    def revert_field
      revert(params[:field].to_s)
    end

    private

    def set_paper_size
      @paper_size = @theme.paper_sizes.find(params[:paper_size_id])
    end

    def set_document_design
      @document_design = @paper_size.document_designs.find(params[:document_design_id])
    end

    def render_preview? = params[:render_preview] != "0"

    def object_fields = @document_design.object_fields

    def set_object_values
      @values = object_values
      head :bad_request unless @values
    end

    # { field => String }: `field` + `value` for one of this doc type's fields,
    # or `values` — exactly one of the sets this doc type writes together
    # (DocumentDesign#object_joint_sets). nil (a 400) for anything else.
    def object_values
      if params.key?(:values)
        set = params[:values]
        return nil unless set.is_a?(ActionController::Parameters)
        values = set.to_unsafe_h.to_h
        return nil unless values.values.all?(String)
        values if @document_design.object_joint_sets.any? { |fields| fields.sort == values.keys.sort }
      else
        field = params[:field].to_s
        value = params[:value]
        { field => value } if object_fields.include?(field) && value.is_a?(String)
      end
    end

    def ensure_object_field
      head :bad_request unless object_fields.include?(params[:field].to_s)
    end

    # update_columns: the default is valid by construction, so a revert can
    # never 422, and a legacy row that fails an unrelated validation (a
    # cover_type outside COVER_TYPES, say) still reverts instead of 500ing —
    # the same call D3 makes for body_line_count. updated_at is written for the
    # preview fingerprint.
    def revert(field)
      @document_design.update_columns(field => revert_value(field), updated_at: Time.current)
      render_saved
    end

    def revert_value(field)
      return nil if Design::DocumentDesign::OBJECT_TEXT_BOX_FIELDS.include?(field)
      Design::DocumentDesign.column_defaults.fetch(field)
    end

    def render_saved
      Design::ThemeDbExportService.new(@theme).export!
      render turbo_stream: object_streams
    end

    # Nothing was written: reload so the section shows stored values around the
    # attempted ones, with each message under its field.
    def render_invalid(values)
      messages = values.keys.index_with { |f| @document_design.errors[f] }.reject { |_, m| m.empty? }
      messages = { values.keys.first => @document_design.errors.full_messages } if messages.empty?
      @document_design.reload
      render turbo_stream: object_streams(field_errors: messages, attempted: values), status: :unprocessable_entity
    end

    # The component is the stream content (render_in: no layout).
    def object_streams(**content)
      component = Design::Views::DocumentDesigns::ObjectSectionContent.new(
        document_design: @document_design, editable: editable?, **content)
      streams = [ turbo_stream.replace(Design::Views::DocumentDesigns::ObjectSectionContent::TARGET, component,
                                       method: :morph) ]
      streams << preview_frame_stream if render_preview?
      streams
    end
  end
end
