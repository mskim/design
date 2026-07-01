# Schema for the design gem's dummy test app.
#
# Contains exactly what the engine's models/tests touch:
#   * design_* tables — copied verbatim from book_write's db/schema.rb.
#   * users — minimal stand-in for the host User (id + role + has_secure_password
#     columns the tests pass), owning custom themes via design_themes.user_id.
#   * action_text_rich_texts + active_storage_* — Design::DocumentDesign
#     has_one_attached :heading_bg_image, and rails/all loads Action Text.

ActiveRecord::Schema[8.1].define(version: 2) do
  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "name"
    t.string "password_digest"
    t.integer "role", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.string "slug"
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
    t.index ["slug"], name: "index_active_storage_attachments_on_slug", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "design_document_designs", force: :cascade do |t|
    t.integer "body_line_count"
    t.integer "column_count", default: 1
    t.string "cover_type", default: "single_any_side"
    t.datetime "created_at", null: false
    t.string "doc_type", null: false
    t.text "footer_left_content_string"
    t.float "footer_left_y_offset", default: 10.0
    t.text "footer_right_content_string"
    t.float "footer_right_y_offset", default: 10.0
    t.string "footnote_char"
    t.string "footnote_range"
    t.string "footnote_type"
    t.decimal "gutter", default: "10.0"
    t.boolean "has_document_cover", default: false
    t.boolean "has_footer", default: true
    t.boolean "has_header", default: false
    t.text "header_left_content_string"
    t.float "header_left_y_offset", default: 10.0
    t.text "header_right_content_string"
    t.float "header_right_y_offset", default: 10.0
    t.string "heading_bg_color", default: "white"
    t.decimal "heading_bg_gradient_angle", default: "0.0"
    t.string "heading_bg_gradient_end"
    t.string "heading_bg_gradient_start"
    t.string "heading_bg_type", default: "color"
    t.integer "heading_height_in_lines", default: 6
    t.string "heading_v_align", default: "center"
    t.integer "image_opacity", default: 100
    t.decimal "logo_height", precision: 6, scale: 2
    t.decimal "logo_offset", precision: 6, scale: 2, default: "0.0"
    t.string "logo_position"
    t.decimal "logo_width", precision: 6, scale: 2
    t.string "toc_v_align"
    t.string "layout_class", default: "RLayout::RDocument"
    t.string "page_bg_color"
    t.integer "page_count"
    t.string "page_type"
    t.integer "paper_size_id", null: false
    t.boolean "show_header_footer_on_first_page", default: false
    t.integer "text_box_anchor_position"
    t.integer "text_box_grid_height"
    t.integer "text_box_grid_width"
    t.datetime "updated_at", null: false
    t.string "v_alignment"
    t.index ["paper_size_id", "doc_type"], name: "idx_design_doc_designs_on_ps_and_doc_type", unique: true
    t.index ["paper_size_id"], name: "index_design_document_designs_on_paper_size_id"
  end

  create_table "design_heading_elements", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "document_design_id", null: false
    t.string "element_type", null: false
    t.integer "position", default: 0, null: false
    t.string "style_name", null: false
    t.datetime "updated_at", null: false
    t.index ["document_design_id", "position"], name: "idx_design_heading_elements_on_dd_and_position"
    t.index ["document_design_id"], name: "index_design_heading_elements_on_document_design_id"
  end

  create_table "design_paper_sizes", force: :cascade do |t|
    t.decimal "binding_margin_mm", default: "0.0", null: false
    t.integer "body_line_count", default: 23, null: false
    t.decimal "bottom_margin_mm", default: "25.0", null: false
    t.datetime "created_at", null: false
    t.decimal "height_mm", null: false
    t.decimal "left_margin_mm", default: "20.0", null: false
    t.string "local_name"
    t.json "overridden_fields", default: [], null: false
    t.decimal "right_margin_mm", default: "20.0", null: false
    t.string "size_name", null: false
    t.integer "theme_id", null: false
    t.integer "toc_page_count", default: 1, null: false
    t.decimal "top_margin_mm", default: "14.0", null: false
    t.datetime "updated_at", null: false
    t.decimal "width_mm", null: false
    t.index ["theme_id", "size_name"], name: "index_design_paper_sizes_on_theme_id_and_size_name", unique: true
    t.index ["theme_id"], name: "index_design_paper_sizes_on_theme_id"
  end

  create_table "design_paragraph_styles", force: :cascade do |t|
    t.string "bold_font"
    t.string "bold_text_color"
    t.string "border_color"
    t.string "border_side"
    t.decimal "border_thickness"
    t.string "corner_radius"
    t.datetime "created_at", null: false
    t.string "emphasis_color"
    t.string "emphasis_font"
    t.string "fill_color"
    t.string "fill_ending_color"
    t.string "fill_gradient_direction"
    t.string "fill_type"
    t.decimal "first_line_indent"
    t.string "font"
    t.decimal "font_size"
    t.string "korean_name"
    t.decimal "left_indent"
    t.string "name", null: false
    t.json "overridden_fields", default: [], null: false
    t.decimal "padding_bottom"
    t.decimal "padding_top"
    t.decimal "right_indent"
    t.string "rounded_corners"
    t.decimal "scale", default: "100.0"
    t.decimal "space_after"
    t.decimal "space_after_in_lines"
    t.decimal "space_before"
    t.decimal "space_before_in_lines"
    t.decimal "space_width"
    t.integer "styleable_id", null: false
    t.string "styleable_type", null: false
    t.string "text_align"
    t.string "text_color", default: "CMYK=0,0,0,100"
    t.decimal "text_line_spacing"
    t.decimal "tracking"
    t.datetime "updated_at", null: false
    t.string "vertical_align"
    t.index ["styleable_type", "styleable_id", "name"], name: "idx_design_para_styles_on_styleable_and_name", unique: true
    t.index ["styleable_type", "styleable_id"], name: "idx_design_para_styles_on_styleable"
  end

  create_table "design_table_styles", force: :cascade do |t|
    t.string "alternate_row_background"
    t.string "body_text_color"
    t.string "border_color"
    t.string "border_style"
    t.decimal "border_width", precision: 6, scale: 2
    t.decimal "cell_padding", precision: 6, scale: 2
    t.datetime "created_at", null: false
    t.string "header_background"
    t.string "header_font_weight"
    t.decimal "header_separator_width", precision: 6, scale: 2
    t.string "header_text_color"
    t.string "name", null: false
    t.decimal "outer_border_width", precision: 6, scale: 2
    t.integer "theme_id", null: false
    t.datetime "updated_at", null: false
    t.index ["theme_id", "name"], name: "index_design_table_styles_on_theme_id_and_name", unique: true
    t.index ["theme_id"], name: "index_design_table_styles_on_theme_id"
  end

  create_table "design_themes", force: :cascade do |t|
    t.string "base_body_font", default: "smShinShinMyungjoP-30", null: false
    t.decimal "base_body_font_size", default: "9.5", null: false
    t.string "base_heading_font", default: "NotoSerifKR-Bold", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "imported_at"
    t.string "locale", default: "ko", null: false
    t.string "name", null: false
    t.string "source_file"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["user_id", "name"], name: "index_design_themes_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_design_themes_on_user_id"
  end
end
