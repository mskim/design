module Design
  class TableStylePreviewsController < Design::ApplicationController
    before_action :set_theme

    def show
      table_style = @theme.table_styles.find(params[:id])
      blob =
        if Design.config.table_style_preview
          Design.config.table_style_preview.call(@theme, table_style)
        else
          Design::TableStylePreviewService.call(@theme, table_style)
        end

      expires_now
      send_data blob, type: "image/jpeg", disposition: "inline"
    rescue ActiveRecord::RecordNotFound
      head :not_found
    rescue => e
      Rails.logger.error("[design] table-style preview failed: #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n")) if e.backtrace
      head :unprocessable_entity
    end
  end
end
