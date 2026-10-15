# Design

A mountable Rails engine providing the shared **book design studio** used by
BookWrite and BookDesign: `Design::` models on `design_*` tables, a Phlex +
scoped-Tailwind editor UI, and the `ThemeDbExportService` / `ThemeImportService`
theme-transfer pipeline.

## Host integration

Mount the engine and wire the host contract in an initializer:

```ruby
# config/routes.rb
mount Design::Engine, at: "/design"

# config/initializers/design.rb
Design.configure do |c|
  c.current_user = -> { Current.user }
  c.authorize    = ->(user) { user&.can_design? }
  c.user_class   = "User"
  c.authoring    = false # true for the vendor authoring host (BookDesign)
  c.home_url     = -> { main_app.root_path }
  c.locale_for   = -> { session[:locale] }
  c.authenticate = -> { ... } # resume the host session; sets the current user
  c.designcraft  = true       # or a lambda: previews laid out by DesignCraft
end
```

With `designcraft` on, the previews of the text pages (chapters and the like, poems, title
pages, TOC, copyright and blank pages) are laid out by DesignCraft through designcraft_rb, as
the host prints its books; the host brings designcraft_rb and designcraft-cli. The cover panels,
wings and document cover, and any preview DesignCraft can't lay out, stay with doc_processor_rb.

The host owns the `design_*` migrations and the `design-controllers` importmap pin
(`pin_all_from Design::Engine.root.join("app/javascript/design-controllers")`).

## Development

This gem is consumed locally via a `path:`/`BUNDLE_LOCAL__DESIGN` override during
development. Its own suite runs against a dummy app under `test/dummy`.
