module Design
  # "Copy for another size": a design has one paper size, so another size is a
  # new design copied from this one (SizedCopyService). Like clone, any
  # designer who can see the design may copy it.
  class SizeCopiesController < Design::ApplicationController
    before_action :set_theme

    def new
      render Design::Views::SizeCopies::Form.new(theme: @theme)
    end

    def create
      size = chosen_size
      return render_form(error: t("design.size_copies.choose_size")) unless size

      service = Design::SizedCopyService.new(@theme, **size, name: size_copy_params[:name])
      copy = service.call
      # The copy exists even when its .db didn't export: open it, saying so.
      if service.export_error
        redirect_to theme_path(copy), alert: t("design.size_copies.export_failed", name: copy.name, error: service.export_error.message)
      else
        redirect_to theme_path(copy), notice: t("design.size_copies.created_notice", name: copy.name)
      end
    rescue ActiveRecord::RecordInvalid, RuntimeError => e
      render_form(error: t("design.size_copies.failed", error: e.message))
    end

    private

    def size_copy_params
      params.fetch(:size_copy, {}).permit(:size, :width_mm, :height_mm, :name)
    end

    # A typed width and height (both, positive) win over the selected size.
    def chosen_size
      width, height = size_copy_params.values_at(:width_mm, :height_mm).map { |v| v.to_s.strip.to_d if v.present? }
      return { width_mm: width, height_mm: height } if width&.positive? && height&.positive?

      Design::PaperSize::STANDARD_SIZES.find { |s| s[:local_name] == size_copy_params[:size] }
    end

    def render_form(error:)
      render Design::Views::SizeCopies::Form.new(theme: @theme, values: size_copy_params.to_h, error: error),
             status: :unprocessable_entity
    end
  end
end
