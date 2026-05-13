# frozen_string_literal: true

require "uri"
require_relative "app_url/version"

class AppUrl
  class << self
    def host
      Rails.application.default_url_options[:host]
    end

    def url_options
      Rails.application.default_url_options
    end

    def base_url
      opts = Rails.application.default_url_options
      return nil unless opts[:host]

      scheme = opts[:protocol] || "https"
      uri = URI("#{scheme}://#{opts[:host]}")
      uri.port = opts[:port] if opts[:port] && opts[:port] != uri.default_port
      uri.to_s
    end

    def public_url
      value = ENV["TUNNEL_URL"]
      return nil if value.nil? || value.empty?

      value
    end

    def public_host
      public_url ? URI(public_url).host : host
    end

    def public_url_options
      return url_options unless public_url

      parsed = URI(public_url)
      opts = { host: parsed.host, protocol: parsed.scheme }
      opts[:port] = parsed.port unless parsed.port == parsed.default_port
      opts
    end

    def public_base_url
      public_url || base_url
    end
  end
end
