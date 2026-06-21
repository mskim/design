module Design
  module Views
    class Base < Phlex::HTML
      include Phlex::Rails::Helpers::Routes
      include Phlex::Rails::Helpers::ButtonTo
      include Phlex::Rails::Helpers::TurboFrameTag
      include RubyUI
    end
  end
end
