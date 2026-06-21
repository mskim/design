# Pin npm packages by running ./bin/importmap

# Wire the design engine's JavaScript exactly as a host app does (mirrors
# book_write's config/importmap.rb): expose the entrypoint as "design" and pin
# the engine's Stimulus controllers under the "design-controllers" prefix so
# eagerLoadControllersFrom("design-controllers", application) discovers them
# (e.g. design-controllers/ruby-ui/tabs_controller.js → "ruby-ui--tabs").
pin "design", to: "design/index.js"
pin_all_from Design::Engine.root.join("app/javascript/design-controllers").to_s, under: "design-controllers"
