# frozen_string_literal: true

require "uri"
require_relative "tunnel_url/version"

class TunnelUrl
  class << self
    def url
      value = ENV["TUNNEL_URL"]
      return nil if value.nil? || value.empty?

      value
    end

    def host
      url && URI(url).host
    end

    def base_url
      opts = Rails.application.default_url_options
      scheme = opts[:protocol] || "https"
      uri = URI("#{scheme}://#{opts[:host]}")
      uri.port = opts[:port] if opts[:port] && opts[:port] != uri.default_port
      uri.to_s
    end

    def public_url_options
      return Rails.application.default_url_options unless url

      parsed = URI(url)
      opts = { host: parsed.host, protocol: parsed.scheme }
      opts[:port] = parsed.port unless parsed.port == parsed.default_port
      opts
    end

    def public_base_url
      url || base_url
    end
  end
end
