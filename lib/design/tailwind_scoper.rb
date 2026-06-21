# frozen_string_literal: true

module Design
  # CSS-aware transform that prefixes/maps every style-rule selector under a
  # scoping class (default ".design-studio") so the engine's Tailwind build
  # cannot affect host pages, even when bundled app-wide via stylesheet_link_tag.
  #
  # Not a line regex: it tokenizes top-level statements with a brace-matching
  # parser, recurses into conditional at-rules (@media/@supports/@layer/@container),
  # and leaves name/keyframe at-rules untouched (@keyframes/@property/@font-face/
  # @counter-style).
  module TailwindScoper
    # At-rules whose bodies contain nested style rules we must scope.
    RECURSE_AT_RULES = %w[media supports layer container].freeze

    # At-rules whose bodies must be left completely untouched (their inner
    # "selectors" are keyframe selectors, property/font/counter descriptors, etc.).
    OPAQUE_AT_RULES = %w[keyframes property font-face counter-style font-feature-values
                         page viewport].freeze

    module_function

    # Returns CSS with every style-rule selector scoped under `under`.
    def scope(css, under: ".design-studio")
      transform(css, under: under)
    end

    # Returns the list of style-rule selectors (outside opaque at-rules) that do
    # NOT contain `under`, i.e. selectors that would leak onto host pages.
    def unscoped_selectors(css, under: ".design-studio")
      offenders = []
      collect_unscoped(css, under, offenders)
      offenders
    end

    # --- internals ---

    # Parse top-level statements and rebuild, scoping/recursing as appropriate.
    def transform(css, under:)
      out = +""
      each_statement(css) do |kind, *parts|
        case kind
        when :at_bodyless
          # e.g. @import url(...); @charset "..."; @layer a,b,c;
          out << parts[0]
        when :at_block
          name, prelude, body = parts
          if RECURSE_AT_RULES.include?(name.downcase)
            out << "@#{name}#{prelude}{#{transform(body, under: under)}}"
          else
            # opaque: leave body untouched
            out << "@#{name}#{prelude}{#{body}}"
          end
        when :rule
          selector, body = parts
          out << "#{scope_selector_list(selector, under)}{#{body}}"
        when :stray
          out << parts[0]
        end
      end
      out
    end

    def collect_unscoped(css, under, offenders)
      each_statement(css) do |kind, *parts|
        case kind
        when :at_block
          name, _prelude, body = parts
          if RECURSE_AT_RULES.include?(name.downcase)
            collect_unscoped(body, under, offenders)
          end
          # opaque at-rules: skip entirely
        when :rule
          selector, _body = parts
          split_selectors(selector).each do |sel|
            offenders << sel unless sel.include?(under)
          end
        end
      end
    end

    # Iterate over top-level CSS statements, yielding tagged tuples.
    # Tags: [:at_bodyless, "raw;"], [:at_block, name, prelude, body],
    #       [:rule, selector, body], [:stray, "raw"]
    def each_statement(css)
      i = 0
      n = css.length
      while i < n
        # skip leading whitespace but preserve nothing meaningful for minified CSS
        start = i
        # find the next significant boundary: ';' (bodyless), '{' (block), or end
        j = i
        depth_ok = true
        token = +""
        # Scan until we hit a top-level '{' or ';' (respecting strings/comments)
        while j < n
          ch = css[j]
          case ch
          when "/"
            if css[j + 1] == "*"
              k = css.index("*/", j + 2)
              k = k ? k + 2 : n
              token << css[j...k]
              j = k
              next
            else
              token << ch
              j += 1
            end
          when '"', "'"
            k = scan_string(css, j)
            token << css[j...k]
            j = k
          when "{"
            break
          when ";"
            # bodyless statement (or stray)
            j += 1
            token << ";"
            stmt = css[start...j]
            yield(*classify_bodyless(stmt))
            i = j
            depth_ok = false
            break
          else
            token << ch
            j += 1
          end
        end
        next unless depth_ok

        if j >= n
          # trailing content with no brace/semicolon
          rest = css[start...n]
          yield(:stray, rest) unless rest.strip.empty?
          break
        end

        # j points at '{' — this is a block (rule or at-block).
        # Peel off any leading comments/whitespace so they pass through verbatim
        # and don't get mistaken for part of a selector (Tailwind emits a banner
        # comment before the first @layer).
        prelude = css[start...j]
        lead, prelude = split_leading_trivia(prelude)
        yield(:stray, lead) unless lead.empty?

        body_start = j + 1
        body_end = match_brace(css, j)
        body = css[body_start...body_end]
        i = body_end + 1

        if prelude.lstrip.start_with?("@")
          name, after = split_at_name(prelude.lstrip)
          yield(:at_block, name, after, body)
        else
          yield(:rule, prelude, body)
        end
      end
    end

    def classify_bodyless(stmt)
      s = stmt.lstrip
      if s.start_with?("@")
        [:at_bodyless, stmt]
      else
        [:stray, stmt]
      end
    end

    # Split off leading whitespace and /* */ comments from a prelude.
    # Returns [leading_trivia, remainder].
    def split_leading_trivia(prelude)
      i = 0
      n = prelude.length
      loop do
        # whitespace
        i += 1 while i < n && prelude[i] =~ /\s/
        # comment
        if prelude[i] == "/" && prelude[i + 1] == "*"
          k = prelude.index("*/", i + 2)
          i = k ? k + 2 : n
        else
          break
        end
      end
      [prelude[0...i], prelude[i..] || ""]
    end

    # Given a prelude beginning with '@', return [name, rest_including_leading_space].
    # e.g. "@media (min-width:40rem)" -> ["media", " (min-width:40rem)"]
    def split_at_name(prelude)
      m = prelude.match(/\A@([A-Za-z-]+)/)
      name = m[1]
      rest = prelude[(1 + name.length)..] || ""
      [name, rest]
    end

    # Index of the closing '}' matching the '{' at position `open`.
    def match_brace(css, open)
      depth = 0
      i = open
      n = css.length
      while i < n
        ch = css[i]
        case ch
        when "/"
          if css[i + 1] == "*"
            k = css.index("*/", i + 2)
            i = k ? k + 2 : n
            next
          end
          i += 1
        when '"', "'"
          i = scan_string(css, i)
        when "{"
          depth += 1
          i += 1
        when "}"
          depth -= 1
          return i if depth.zero?
          i += 1
        else
          i += 1
        end
      end
      n - 1
    end

    # Return index just past the closing quote of the string starting at `i`.
    def scan_string(css, i)
      quote = css[i]
      j = i + 1
      n = css.length
      while j < n
        c = css[j]
        if c == "\\"
          j += 2
          next
        end
        if c == quote
          return j + 1
        end
        j += 1
      end
      n
    end

    # Split a selector list on top-level commas (ignoring commas inside
    # (), [], strings — e.g. :is(a, b), [attr="x,y"]).
    def split_selectors(selector)
      parts = []
      buf = +""
      depth = 0
      i = 0
      n = selector.length
      while i < n
        ch = selector[i]
        case ch
        when "(", "["
          depth += 1
          buf << ch
          i += 1
        when ")", "]"
          depth -= 1
          buf << ch
          i += 1
        when '"', "'"
          k = scan_string(selector, i)
          buf << selector[i...k]
          i = k
        when ","
          if depth.zero?
            parts << buf.strip
            buf = +""
            i += 1
          else
            buf << ch
            i += 1
          end
        else
          buf << ch
          i += 1
        end
      end
      parts << buf.strip unless buf.strip.empty?
      parts
    end

    # Scope a full selector list, joining back with commas.
    def scope_selector_list(selector, under)
      split_selectors(selector).map { |sel| scope_one(sel, under) }.join(",")
    end

    # Tokens that represent the document root / universal reach. When a selector
    # is exactly one of these (or a pseudo-element on its own), it must be mapped
    # so the rule only ever applies inside `under`.
    ROOT_TOKENS = %w[* html body :root].freeze
    BARE_PSEUDO = /\A::?[A-Za-z-]+(\([^)]*\))?\z/.freeze

    def scope_one(sel, under)
      s = sel.strip
      return s if s.empty?
      return s if already_scoped?(s, under)

      # :root -> the scope element itself
      if s == ":root"
        return under
      end

      # Universal / root-ish single tokens: map to `under *`-style reach so the
      # reset only applies inside the scope, never to the host document.
      if ROOT_TOKENS.include?(s)
        return s == "*" ? "#{under} *" : "#{under} #{s}"
      end

      # Bare pseudo-elements like ::before / ::after / ::backdrop apply to all
      # elements; scope them under the universal descendant of `under`.
      if s.start_with?("::") && s.match?(BARE_PSEUDO)
        return "#{under} *#{s}"
      end

      # A leading combinator (>, +, ~) is unusual at list-top; leave as-is prefix.
      "#{under} #{s}"
    end

    def already_scoped?(sel, under)
      sel == under || sel.include?(under)
    end
  end
end
