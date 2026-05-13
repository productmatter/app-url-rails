# frozen_string_literal: true

require "rails/generators"

module TunnelUrl
  module Generators
    class InstallGenerator < Rails::Generators::Base
      DEVELOPMENT_RB = "config/environments/development.rb"

      WIRING = <<~RUBY
        # tunnel-url-rails: outsider-reachable URLs in development.
        # Must run at config-time — Rails snapshots config.hosts during initialize!,
        # so adding hosts later (initializer, after_initialize) is silently ignored.
        if (tunnel = ENV["TUNNEL_URL"]) && !tunnel.empty?
          require "uri"
          uri = URI(tunnel)
          config.hosts << uri.host
          routes.default_url_options = { host: uri.host, protocol: uri.scheme }
        end
      RUBY

      def inject_wiring
        unless File.exist?(DEVELOPMENT_RB)
          say_status :error, "#{DEVELOPMENT_RB} not found — is this a Rails app?", :red
          return
        end

        if File.read(DEVELOPMENT_RB).include?("TUNNEL_URL")
          say_status :skip, "#{DEVELOPMENT_RB} already references TUNNEL_URL", :yellow
          return
        end

        indented = WIRING.each_line.map { |line| line.strip.empty? ? line : "  #{line}" }.join

        inject_into_file DEVELOPMENT_RB, "\n#{indented}", after: /Rails\.application\.configure do\n/
      end
    end
  end
end
