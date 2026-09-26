# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/app_url"

module Rails
  class << self
    attr_accessor :application
  end
end

class AppUrlConfigurationTest < Minitest::Test
  class Application
    attr_accessor :default_url_options

    def initialize
      @default_url_options = {}
    end
  end

  class CableOptions
    attr_accessor :allowed_request_origins

    def initialize(origins)
      @allowed_request_origins = origins
    end
  end

  class CableConfiguration
    attr_reader :action_cable, :hosts

    def initialize(hosts: [], origins: nil)
      @hosts = hosts
      @action_cable = CableOptions.new(origins)
    end
  end

  class ConfigurationWithoutCable
    attr_reader :hosts

    def initialize(hosts: [])
      @hosts = hosts
    end
  end

  INVALID_ENVIRONMENT_URLS = [
    " \t ",
    "example.com",
    "ftp://example.com",
    "https://",
    "https://user:secret@example.com",
    "https://@example.com",
    "https://example.com/path",
    "https://example.com?query",
    "https://example.com#fragment",
    "https://example.com:",
    "https://example.com:port",
    "https://example.com:0",
    "https://example.com:65536",
    "https://::1",
    "https://[malformed",
    "https://example.com/\xFF".b
  ].freeze

  def setup
    @saved_dev_url = ENV["DEV_URL"]
    @saved_tunnel_url = ENV["TUNNEL_URL"]
    ENV.delete("DEV_URL")
    ENV.delete("TUNNEL_URL")
    Rails.application = Application.new
  end

  def teardown
    restore_environment("DEV_URL", @saved_dev_url)
    restore_environment("TUNNEL_URL", @saved_tunnel_url)
    Rails.application = nil
  end

  def test_no_environment_urls_make_no_changes
    defaults = { host: "existing.example", protocol: "https", locale: "en" }
    hosts = ["existing.example"]
    origins = "https://existing-origin.example"
    Rails.application.default_url_options = defaults
    config = CableConfiguration.new(hosts:, origins:)

    AppUrl.configure_development!(config)

    assert_same defaults, Rails.application.default_url_options
    assert_equal({ host: "existing.example", protocol: "https", locale: "en" }, defaults)
    assert_equal ["existing.example"], hosts
    assert_same origins, config.action_cable.allowed_request_origins
  end

  def test_dev_url_merges_address_options_and_clears_a_stale_default_port
    defaults = { host: "old.example", protocol: "http", port: 3000, locale: "en" }
    Rails.application.default_url_options = defaults
    config = ConfigurationWithoutCable.new
    ENV["DEV_URL"] = "https://dev.example:443/"

    AppUrl.configure_development!(config)

    assert_equal({ host: "dev.example", protocol: "https", locale: "en" },
                 Rails.application.default_url_options)
    assert_equal({ host: "old.example", protocol: "http", port: 3000, locale: "en" }, defaults)
    assert_equal ["dev.example"], config.hosts
  end

  def test_dev_url_keeps_a_non_default_port
    original = { locale: "en" }.freeze
    Rails.application.default_url_options = original
    config = ConfigurationWithoutCable.new
    ENV["DEV_URL"] = "http://dev.example:3100"

    AppUrl.configure_development!(config)

    assert_equal({ host: "dev.example", protocol: "http", port: 3100, locale: "en" },
                 Rails.application.default_url_options)
    assert_equal({ locale: "en" }, original)
    refute_same original, Rails.application.default_url_options
  end

  def test_tunnel_url_does_not_change_route_defaults
    defaults = { host: "existing.example", protocol: "https", locale: "en" }
    Rails.application.default_url_options = defaults
    config = ConfigurationWithoutCable.new
    ENV["TUNNEL_URL"] = "https://tunnel.example"

    AppUrl.configure_development!(config)

    assert_same defaults, Rails.application.default_url_options
    assert_equal({ host: "existing.example", protocol: "https", locale: "en" }, defaults)
    assert_equal ["tunnel.example"], config.hosts
  end

  def test_setup_preserves_allowances_and_is_idempotent
    preserved_regexp = %r{\Ahttps://preserved\.example\z}
    config = CableConfiguration.new(
      hosts: ["preserved.example"],
      origins: ["https://string-origin.example", preserved_regexp]
    )
    ENV["DEV_URL"] = "http://dev.example:3100"
    ENV["TUNNEL_URL"] = "https://tunnel.example:4443"

    2.times { AppUrl.configure_development!(config) }

    assert_equal ["preserved.example", "dev.example", "tunnel.example"], config.hosts
    assert_equal 4, config.action_cable.allowed_request_origins.size
    assert_includes config.action_cable.allowed_request_origins, "https://string-origin.example"
    assert_includes config.action_cable.allowed_request_origins, preserved_regexp
    assert cable_allowed?(config, "http://dev.example:99999")
    assert cable_allowed?(config, "https://tunnel.example")
    refute cable_allowed?(config, "https://dev.example:3100")
    refute cable_allowed?(config, "https://tunnel.example.evil:4443")
  end

  def test_setup_converts_a_single_cable_origin_without_losing_it
    config = CableConfiguration.new(origins: "https://existing-origin.example")
    ENV["TUNNEL_URL"] = "https://tunnel.example"

    AppUrl.configure_development!(config)

    origins = config.action_cable.allowed_request_origins
    assert_equal "https://existing-origin.example", origins.first
    assert_equal 2, origins.size
    assert cable_allowed?(config, "https://tunnel.example:99999")
  end

  def test_setup_supports_ipv6_hosts
    config = CableConfiguration.new
    ENV["DEV_URL"] = "http://[::1]:3000/"

    AppUrl.configure_development!(config)

    assert_equal({ host: "[::1]", protocol: "http", port: 3000 },
                 Rails.application.default_url_options)
    assert_equal ["[::1]"], config.hosts
    assert cable_allowed?(config, "http://[::1]:99999")
    refute cable_allowed?(config, "http://[::1].evil:3000")
  end

  def test_both_urls_are_validated_before_any_mutation
    defaults = { host: "existing.example", protocol: "https", port: 4443 }
    hosts = ["existing.example"]
    origins = ["https://existing-origin.example"]
    Rails.application.default_url_options = defaults
    config = CableConfiguration.new(hosts:, origins:)
    ENV["DEV_URL"] = "http://dev.example:3100"
    ENV["TUNNEL_URL"] = "https://user:secret-sentinel@tunnel.example"

    error = assert_raises(AppUrl::ConfigurationError) { AppUrl.configure_development!(config) }

    assert_match(/TUNNEL_URL.*userinfo/, error.message)
    refute_includes error.full_message, "secret-sentinel"
    assert_nil error.cause
    assert_equal({ host: "existing.example", protocol: "https", port: 4443 }, defaults)
    assert_equal ["existing.example"], hosts
    assert_equal ["https://existing-origin.example"], origins
  end

  def test_setup_rejects_every_invalid_dev_url_category
    INVALID_ENVIRONMENT_URLS.each do |value|
      ENV["DEV_URL"] = value
      config = ConfigurationWithoutCable.new

      error = assert_raises(AppUrl::ConfigurationError) { AppUrl.configure_development!(config) }
      assert_match(/DEV_URL/, error.message)
      assert_nil error.cause
      assert_empty config.hosts
      assert_empty Rails.application.default_url_options
    end
  end

  private

  def cable_allowed?(config, origin)
    Array(config.action_cable.allowed_request_origins).any? { |allowed| allowed === origin }
  end

  def restore_environment(name, value)
    value.nil? ? ENV.delete(name) : ENV[name] = value
  end
end
