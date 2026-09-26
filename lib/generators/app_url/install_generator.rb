# frozen_string_literal: true

require "rails/generators"
require "ripper"

class AppUrl
  module Generators
    class InstallGenerator < Rails::Generators::Base
      DEVELOPMENT_RB = "config/environments/development.rb"
      FORMAT_MARKER = "# app-url-rails: configuration v1"
      SETUP_CALL = "AppUrl.configure_development!(config)"
      LEGACY_MARKER = "# app-url-rails: dev URL + tunnel URL wiring."

      def self.exit_on_failure?
        true
      end

      def install
        fail_install("#{DEVELOPMENT_RB} not found; run this generator from a Rails application root") unless
          File.file?(DEVELOPMENT_RB)

        source = File.binread(DEVELOPMENT_RB)
        syntax_tree = Ripper.sexp(source)
        fail_install("#{DEVELOPMENT_RB} is not valid Ruby; fix its syntax before installing app-url-rails") unless
          syntax_tree

        configure_block = standard_configure_block(syntax_tree, source)
        unless configure_block
          fail_install(
            "#{DEVELOPMENT_RB} must contain exactly one standard `Rails.application.configure do` block; " \
            "add or restore that block before installing app-url-rails"
          )
        end

        comments = Ripper.lex(source).select { |token| token[1] == :on_comment }
        format_markers = comments.select { |token| token[2].match?(/\A# app-url-rails: configuration\b/) }
        app_url_calls = find_nodes(syntax_tree) { |node| app_url_setup_call?(node) }

        if current_installation?(source, configure_block, format_markers, app_url_calls, syntax_tree)
          say_status :skip, "app-url-rails configuration v1 is already installed", :yellow
          return
        end

        if format_markers.any? { |token| token[2].strip != FORMAT_MARKER }
          fail_install(
            "#{DEVELOPMENT_RB} contains an unsupported app-url-rails configuration marker; " \
            "resolve it manually before running the generator"
          )
        end

        if legacy_installation?(comments, syntax_tree)
          fail_install(
            "Legacy app-url-rails wiring detected in #{DEVELOPMENT_RB}. Migrate it manually once: " \
            "remove the complete old generated helper and DEV_URL/TUNNEL_URL branches, preserve surrounding " \
            "configuration, then add `#{FORMAT_MARKER}` and `#{SETUP_CALL}` inside the configure block"
          )
        end

        if format_markers.any? || app_url_calls.any? || environment_reference?(syntax_tree, "DEV_URL") ||
           environment_reference?(syntax_tree, "TUNNEL_URL") || legacy_marker?(comments)
          fail_install(
            "#{DEVELOPMENT_RB} contains partial, custom, or misplaced app-url-rails wiring; " \
            "resolve it manually before running the generator"
          )
        end

        updated = insert_installation(source, configure_block)
        File.binwrite(DEVELOPMENT_RB, updated)
        say_status :insert, DEVELOPMENT_RB, :green
      end

      private

      def fail_install(message)
        raise Thor::Error, message
      end

      def standard_configure_block(syntax_tree, source)
        blocks = find_nodes(syntax_tree) { |node| rails_configure_block?(node) }
        return unless blocks.one?

        block = blocks.first
        return unless syntax_tree[1].any? { |statement| statement.equal?(block) }

        configure_token = block[1][3]
        line_number = configure_token[2][0]
        line = source.lines[line_number - 1]&.delete_suffix("\n")&.delete_suffix("\r")
        return unless line == "Rails.application.configure do"
        return unless block[2][0] == :do_block && block[2][1].nil?

        block
      end

      def rails_configure_block?(node)
        return false unless node[0] == :method_add_block

        call = node[1]
        return false unless call.is_a?(Array) && call[0] == :call && call[3][1] == "configure"

        application_call = call[1]
        application_call.is_a?(Array) && application_call[0] == :call &&
          application_call[3][1] == "application" && const_receiver?(application_call[1], "Rails")
      end

      def app_url_setup_call?(node)
        %i[call command_call].include?(node[0]) && node[3][1] == "configure_development!" &&
          const_receiver?(node[1], "AppUrl")
      end

      def const_receiver?(node, name)
        node.is_a?(Array) && %i[var_ref top_const_ref].include?(node[0]) &&
          node[1][0] == :@const && node[1][1] == name
      end

      def current_installation?(source, configure_block, format_markers, app_url_calls, syntax_tree)
        return false unless format_markers.one? && format_markers.first[2].strip == FORMAT_MARKER
        return false unless app_url_calls.one? && direct_configure_statement?(configure_block, app_url_calls.first)
        return false if environment_reference?(syntax_tree, "DEV_URL") || environment_reference?(syntax_tree, "TUNNEL_URL")

        call_line_number = app_url_calls.first[3][2][0]
        lines = source.lines
        marker_line = lines[call_line_number - 2]&.delete_suffix("\n")&.delete_suffix("\r")
        call_line = lines[call_line_number - 1]&.delete_suffix("\n")&.delete_suffix("\r")

        marker_line == "  #{FORMAT_MARKER}" && call_line == "  #{SETUP_CALL}" &&
          format_markers.first[0][0] == call_line_number - 1
      end

      def legacy_installation?(comments, syntax_tree)
        legacy_marker?(comments) &&
          environment_reference?(syntax_tree, "DEV_URL") &&
          environment_reference?(syntax_tree, "TUNNEL_URL") &&
          identifier?(syntax_tree, "app_url_origin") &&
          identifier?(syntax_tree, "allowed_request_origins")
      end

      def legacy_marker?(comments)
        comments.any? { |token| token[2].strip == LEGACY_MARKER }
      end

      def environment_reference?(syntax_tree, name)
        find_nodes(syntax_tree).any? do |node|
          if node[0] == :aref
            const_receiver?(node[1], "ENV") && string_content?(node[2], name)
          elsif node[0] == :method_add_arg
            env_fetch_call?(node[1]) && string_content?(node[2], name)
          elsif node[0] == :command_call
            const_receiver?(node[1], "ENV") && node[3][1] == "fetch" && string_content?(node[4], name)
          else
            false
          end
        end
      end

      def env_fetch_call?(node)
        node.is_a?(Array) && node[0] == :call && node[3][1] == "fetch" && const_receiver?(node[1], "ENV")
      end

      def string_content?(tree, value)
        tree.flatten.each_cons(2).any? { |type, content| type == :@tstring_content && content == value }
      end

      def identifier?(syntax_tree, name)
        find_nodes(syntax_tree).any? do |node|
          %i[@ident @label].include?(node[0]) && node[1].delete_suffix(":") == name
        end
      end

      def insert_installation(source, configure_block)
        line_number = configure_block[1][3][2][0]
        newline = source.include?("\r\n") ? "\r\n" : "\n"
        insertion_offset = source.lines.first(line_number).sum(&:bytesize)
        installation = "  #{FORMAT_MARKER}#{newline}  #{SETUP_CALL}#{newline}"

        source.dup.insert(insertion_offset, installation)
      end

      def direct_configure_statement?(configure_block, call)
        statements = configure_block.dig(2, 2, 1) || []
        statements.any? do |statement|
          statement[0] == :method_add_arg && statement[1].equal?(call)
        end
      end

      def find_nodes(tree, matches = [], &predicate)
        return matches unless tree.is_a?(Array)

        matches << tree if predicate.nil? || predicate.call(tree)
        tree.each { |child| find_nodes(child, matches, &predicate) if child.is_a?(Array) }
        matches
      end
    end
  end
end
