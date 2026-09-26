# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/app_url"

require_relative "support/app_url_test_support"

class AppUrlConfigurationTest < Minitest::Test
  include AppUrlTestSupport

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

  def setup
    super
    @saved_dev_url = ENV["DEV_URL"]
    @saved_tunnel_url = ENV["TUNNEL_URL"]
    ENV.delete("DEV_URL")
    ENV.delete("TUNNEL_URL")
  end

  def teardown
    restore_environment("DEV_URL", @saved_dev_url)
    restore_environment("TUNNEL_URL", @saved_tunnel_url)
    super
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
    assert_equal [
      "https://string-origin.example",
      preserved_regexp,
      %r{\Ahttp://dev\.example(?::\d+)?\z}i,
      %r{\Ahttps://tunnel\.example(?::\d+)?\z}i
    ], config.action_cable.allowed_request_origins
    assert_same preserved_regexp, config.action_cable.allowed_request_origins[1]
  end

  def test_setup_converts_a_single_cable_origin_without_losing_it
    config = CableConfiguration.new(origins: "https://existing-origin.example")
    ENV["TUNNEL_URL"] = "https://tunnel.example"

    AppUrl.configure_development!(config)

    origins = config.action_cable.allowed_request_origins
    assert_equal [
      "https://existing-origin.example",
      %r{\Ahttps://tunnel\.example(?::\d+)?\z}i
    ], origins
  end

  def test_setup_supports_ipv6_hosts
    config = CableConfiguration.new(origins: [])
    ENV["DEV_URL"] = "http://[::1]:3000/"

    AppUrl.configure_development!(config)

    assert_equal({ host: "[::1]", protocol: "http", port: 3000 },
                 Rails.application.default_url_options)
    assert_equal ["[::1]"], config.hosts
    assert_equal [%r{\Ahttp://\[::1\](?::\d+)?\z}i], config.action_cable.allowed_request_origins
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

  %w[DEV_URL TUNNEL_URL].each do |setting|
    define_method("test_setup_rejects_every_invalid_#{setting.downcase}_category_safely") do
      INVALID_ENVIRONMENT_URLS.each do |category, (value, reason)|
        ENV[setting] = value
        config = ConfigurationWithoutCable.new

        error = assert_raises(AppUrl::ConfigurationError, category) { AppUrl.configure_development!(config) }
        assert_safe_configuration_error(error, setting, category, value, reason)
        assert_empty config.hosts
        assert_empty Rails.application.default_url_options
      end
    end
  end

  private

  def restore_environment(name, value)
    value.nil? ? ENV.delete(name) : ENV[name] = value
  end
end
