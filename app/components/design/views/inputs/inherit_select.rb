module Design
  module Views
    module Inputs
      # A <select> whose first option ("") means "inherit": "상속 (<parent>)",
      # grey italic while selected. A current value missing from `options` is
      # added so it round-trips unchanged. A named select gets a stable id
      # ("sel-paragraph_style-font"), so a <label for> names it and a morph keeps it.
      class InheritSelect < Design::Views::Base
        CLASS = "#{Design::Views::FieldGroups::CONTROL} data-[inherited]:italic data-[inherited]:text-slate-400".freeze

        def initialize(name:, value:, options:, inherited_value: nil, i18n_scope: nil, disabled: false, id: nil)
          @name = name
          @id = id || (self.class.default_id(name) if name.present?)
          @value = value.to_s.presence
          @options = options
          @inherited = inherited_value.to_s.presence
          @i18n_scope = i18n_scope
          @disabled = disabled
        end

        def view_template
          select(id: @id, name: @name, class: CLASS, disabled: (true if @disabled), data: { inherited: (true unless @value) }) do
            option(value: "", selected: @value.nil?) { inherit_label }
            all_options.each { |opt| option(value: opt, selected: opt == @value) { label_for(opt) } }
          end
        end

        def self.default_id(name) = "sel-#{NumberField.dom_key(name)}"

        private

        def inherit_label
          @inherited ? I18n.t("design.inputs.inherit_with_value", value: label_for(@inherited)) : I18n.t("design.inputs.inherit")
        end

        def all_options = @value && !@options.include?(@value) ? @options + [ @value ] : @options

        def label_for(opt) = @i18n_scope && @options.include?(opt) ? I18n.t("design.options.#{@i18n_scope}.#{opt}") : opt.to_s
      end
    end
  end
end
