# frozen_string_literal: true

require "rails/generators"

module AppUrl
  module Generators
    class InstallGenerator < Rails::Generators::Base
      DEVELOPMENT_RB = "config/environments/development.rb"

      WIRING = <<~RUBY
        # app-url-rails: dev URL + tunnel URL wiring.
        # Must run at config-time — Rails snapshots config.hosts during initialize!,
        # so adding hosts later (initializer, after_initialize) is silently ignored.
        require "uri"

        if (dev = ENV["DEV_URL"]) && !dev.empty?
          uri = URI(dev)
          config.hosts << uri.host
          opts = { host: uri.host, protocol: uri.scheme }
          opts[:port] = uri.port unless uri.port == uri.default_port
          Rails.application.default_url_options = opts
        end

        if (tunnel = ENV["TUNNEL_URL"]) && !tunnel.empty?
          config.hosts << URI(tunnel).host
        end
      RUBY

      def inject_wiring
        unless File.exist?(DEVELOPMENT_RB)
          say_status :error, "#{DEVELOPMENT_RB} not found — is this a Rails app?", :red
          return
        end

        contents = File.read(DEVELOPMENT_RB)
        if contents.include?("DEV_URL") || contents.include?("TUNNEL_URL")
          say_status :skip, "#{DEVELOPMENT_RB} already references DEV_URL or TUNNEL_URL", :yellow
          return
        end

        indented = WIRING.each_line.map { |line| line.strip.empty? ? line : "  #{line}" }.join

        inject_into_file DEVELOPMENT_RB, "\n#{indented}", after: /Rails\.application\.configure do\n/
      end
    end
  end
end
