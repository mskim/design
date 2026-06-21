module Design
  class Engine < ::Rails::Engine
    isolate_namespace Design

    initializer "design.i18n" do
      config.i18n.load_path += Dir[root.join("config", "locales", "*.yml")]
    end

    initializer "design.ruby_ui" do
      RubyUI.extend(Phlex::Kit) unless RubyUI.singleton_class.include?(Phlex::Kit)
      Rails.autoloaders.main.inflector.inflect("ruby_ui" => "RubyUI")
      ruby_ui_dir = Design::Engine.root.join("app/components/ruby_ui")
      Rails.autoloaders.main.push_dir(ruby_ui_dir, namespace: RubyUI)
      Rails.autoloaders.main.collapse(ruby_ui_dir.join("*"))
    end

    initializer "design.assets" do |app|
      app.config.assets.paths << root.join("app/javascript")
    end

    initializer "design.themes_dir" do
      Design.themes_dir ||= ENV.fetch("THEMES_DIR") { Rails.root.join("storage/themes").to_s }
    end
  end
end
