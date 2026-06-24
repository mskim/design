module Design
  class TableStylePreviewsController < Design::ApplicationController
    before_action :set_theme

    def show
      table_style = @theme.table_styles.find(params[:id])
      blob = Design.config.table_style_preview&.call(@theme, table_style)
      return head :not_found unless blob

      expires_now
      send_data blob, type: "image/jpeg", disposition: "inline"
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end
  end
end
