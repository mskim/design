module Design
  # "Copy for another size": a design has one paper size, so another size is
  # another design. The source's (default) size is cloned into a new theme,
  # resized, and rescaled from the source with SizeGenerationService's rules.
  #
  # The size is a STANDARD_SIZES entry (size_name, local_name, en_name, W, H) or
  # just width_mm/height_mm for a custom one. The name defaults to
  # "<source name> <size label>": the size's Korean name for a Korean source,
  # else an ASCII label (a design's language comes from its file name, so a
  # non-Korean design never carries Hangul).
  #
  # The owner follows clone's rules: a system source on an authoring host gives
  # a system copy; otherwise the current user's custom copy (with no one signed
  # in — console, rake — the source's owner keeps it).
  #
  # The copy is committed before its .db is written, so an export failure is
  # kept in export_error, not raised: the copy exists either way.
  #
  # Usage:
  #   Design::SizedCopyService.new(theme, **Design::PaperSize::STANDARD_SIZES.first).call
  #   Design::SizedCopyService.new(theme, width_mm: 150, height_mm: 220, name: "Pocket").call
  class SizedCopyService
    def initialize(source, width_mm:, height_mm:, size_name: nil, local_name: nil, en_name: nil, name: nil)
      @source = source
      @width_mm = width_mm.to_d
      @height_mm = height_mm.to_d
      w, h = PaperSize.mm_label(@width_mm), PaperSize.mm_label(@height_mm)
      @size_name = size_name.presence || "#{w}mmx#{h}mm"
      @local_name = local_name.presence || "#{w}x#{h}"
      @en_name = en_name
      @name = name
    end

    attr_reader :export_error

    def call
      from = @source.default_paper_size or raise "No paper size to copy on #{@source.name}"

      copy = ActiveRecord::Base.transaction do
        theme = ThemeCloneService.new(@source, user: owner, paper_size: from, name: copy_name).clone
        to = theme.paper_sizes.sole
        to.update!(size_name: @size_name, local_name: @local_name, width_mm: @width_mm, height_mm: @height_mm)
        SizeGenerationService.new(theme).rescale!(from: from, to: to)
        theme.reload
      end
      export(copy)
      copy
    end

    private

    def owner = @source.system? && Design.authoring? ? nil : (Design.current_user || @source.user)

    def export(copy)
      ThemeDbExportService.new(copy).export!
    rescue StandardError => e
      Rails.logger.error("[SizedCopyService] #{copy.name}: .db export failed: #{e.class}: #{e.message}")
      @export_error = e
    end

    def copy_name
      @name.presence&.strip ||
        "#{@source.name} #{PaperSize.name_label(@source.locale, local_name: @local_name, en_name: @en_name,
                                                 width_mm: @width_mm, height_mm: @height_mm)}"
    end
  end
end
