# frozen_string_literal: true

require "action_dispatch/http/url"
require "uri"
require_relative "app_url/version"

class AppUrl
  class ConfigurationError < ArgumentError; end

  class << self
    def host
      Rails.application.default_url_options[:host]
    end

    def url_options
      Rails.application.default_url_options
    end

    def base_url
      options = address_options(url_options)
      return nil unless options[:host]

      ActionDispatch::Http::URL.full_url_for(options)
    end

    def public_url
      environment_origin("TUNNEL_URL")&.fetch(:value)
    end

    def public_host
      origin = environment_origin("TUNNEL_URL")
      origin ? origin.fetch(:host) : host
    end

    def public_url_options
      origin = environment_origin("TUNNEL_URL")
      origin ? public_origin_options(origin) : url_options
    end

    def public_base_url
      origin = environment_origin("TUNNEL_URL")
      origin ? ActionDispatch::Http::URL.full_url_for(public_origin_options(origin)) : base_url
    end

    def configure_development!(config)
      development_origin = environment_origin("DEV_URL")
      tunnel_origin = environment_origin("TUNNEL_URL")
      return unless development_origin || tunnel_origin

      apply_development_origin(development_origin) if development_origin

      [development_origin, tunnel_origin].compact.each do |origin|
        append_once(config.hosts, origin.fetch(:host))
        append_cable_origin(config, origin) if config.respond_to?(:action_cable)
      end
    end

    private

    def address_options(options)
      options.slice(:host, :protocol, :port)
    end

    def environment_origin(setting)
      value = ENV[setting]
      return nil if value.nil? || value.empty?

      configuration_error(setting, "is malformed") unless value.valid_encoding?
      configuration_error(setting, "must not be blank") if value.strip.empty?
      unless value.match?(/\Ahttps?:\/\//i)
        configuration_error(setting, "must include an http:// or https:// scheme")
      end

      authority = value.match(/\Ahttps?:\/\/([^\/?#]*)/i)[1]
      configuration_error(setting, "must not include userinfo") if authority.include?("@")
      validate_port!(setting, authority)

      uri = URI.parse(value)
      configuration_error(setting, "must include a host") if uri.host.nil? || uri.host.empty?
      unless uri.is_a?(URI::HTTP) && %w[http https].include?(uri.scheme)
        configuration_error(setting, "must use the http:// or https:// scheme")
      end
      configuration_error(setting, "must not include userinfo") if uri.userinfo
      unless uri.path.empty? || uri.path == "/"
        configuration_error(setting, "must not include a path beyond a trailing slash")
      end
      configuration_error(setting, "must not include a query") unless uri.query.nil?
      configuration_error(setting, "must not include a fragment") unless uri.fragment.nil?

      { value:, scheme: uri.scheme, host: uri.host, port: uri.port, default_port: uri.default_port }
    rescue URI::Error
      configuration_error(setting, "is malformed")
    end

    def validate_port!(setting, authority)
      port = if authority.start_with?("[")
               closing_bracket = authority.index("]")
               return unless closing_bracket

               remainder = authority[(closing_bracket + 1)..]
               return if remainder.empty?
               configuration_error(setting, "has an invalid host") unless remainder.start_with?(":")

               remainder.delete_prefix(":")
             elsif authority.count(":") == 1
               authority.split(":", 2).last
             elsif authority.count(":") > 1
               configuration_error(setting, "must bracket an IPv6 host")
             else
               return
             end

      unless port.match?(/\A\d+\z/) && port.to_i.between?(1, 65_535)
        configuration_error(setting, "port must be an integer from 1 through 65535")
      end
    end

    def configuration_error(setting, reason)
      message = "#{setting} #{reason}; expected an absolute http:// or https:// URL with a host, " \
                "optional port, and optional trailing slash"
      raise ConfigurationError, message, cause: nil
    end

    def origin_options(origin)
      options = { host: origin.fetch(:host), protocol: origin.fetch(:scheme) }
      options[:port] = origin.fetch(:port) unless origin.fetch(:port) == origin.fetch(:default_port)
      options
    end

    def public_origin_options(origin)
      {
        host: origin.fetch(:host),
        protocol: origin.fetch(:scheme),
        port: origin.fetch(:port)
      }
    end

    def apply_development_origin(origin)
      defaults = Rails.application.default_url_options
      Rails.application.default_url_options = defaults.except(:port).merge(origin_options(origin))
    end

    def append_cable_origin(config, origin)
      origins = Array(config.action_cable.allowed_request_origins)
      config.action_cable.allowed_request_origins = origins
      pattern = %r{\A#{Regexp.escape(origin.fetch(:scheme))}://#{Regexp.escape(origin.fetch(:host))}(?::\d+)?\z}i
      append_once(origins, pattern)
    end

    def append_once(collection, value)
      collection << value unless collection.include?(value)
    end
  end
end
