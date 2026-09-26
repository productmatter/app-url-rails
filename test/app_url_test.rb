# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/app_url"

module Rails
  class << self
    attr_accessor :application
  end
end

class FakeApplication
  attr_accessor :default_url_options

  def initialize
    @default_url_options = {}
  end
end

class AppUrlTest < Minitest::Test
  INVALID_TUNNEL_URLS = {
    "blank" => " \t ",
    "scheme-less" => "credential-sentinel.example",
    "unsupported scheme" => "ftp://credential-sentinel.example",
    "missing host" => "https://",
    "userinfo" => "https://user:credential-sentinel@example.com",
    "empty userinfo" => "https://@example.com",
    "path" => "https://example.com/path-sentinel",
    "query" => "https://example.com?query-sentinel",
    "fragment" => "https://example.com#fragment-sentinel",
    "empty port" => "https://example.com:",
    "non-integer port" => "https://example.com:port-sentinel",
    "zero port" => "https://example.com:0",
    "oversized port" => "https://example.com:65536",
    "unbracketed IPv6" => "https://::1",
    "malformed" => "https://[malformed-sentinel",
    "invalid encoding" => "https://example.com/\xFF".b
  }.freeze
  PUBLIC_HELPERS = %i[public_url public_host public_url_options public_base_url].freeze
  SENTINEL_PATTERN = /credential-sentinel|path-sentinel|query-sentinel|fragment-sentinel|
                      port-sentinel|malformed-sentinel/x

  def setup
    @saved_tunnel_url = ENV["TUNNEL_URL"]
    @saved_secure_protocol = ActionDispatch::Http::URL.secure_protocol
    ENV.delete("TUNNEL_URL")
    Rails.application = FakeApplication.new
  end

  def teardown
    @saved_tunnel_url.nil? ? ENV.delete("TUNNEL_URL") : ENV["TUNNEL_URL"] = @saved_tunnel_url
    ActionDispatch::Http::URL.secure_protocol = @saved_secure_protocol
    Rails.application = nil
  end

  def test_host_returns_configured_host_without_reading_tunnel_url
    ENV["TUNNEL_URL"] = "not a URL"
    Rails.application.default_url_options = { host: "example.com" }

    assert_equal "example.com", AppUrl.host
  end

  def test_host_returns_nil_when_missing
    assert_nil AppUrl.host
  end

  def test_url_options_is_the_exact_application_object
    options = { host: "example.com", protocol: "https", locale: "en" }
    Rails.application.default_url_options = options

    assert_same options, AppUrl.url_options
    assert_equal options, AppUrl.url_options
  end

  def test_url_options_does_not_read_tunnel_url
    ENV["TUNNEL_URL"] = "not a URL"
    options = { host: "example.com" }
    Rails.application.default_url_options = options

    assert_same options, AppUrl.url_options
  end

  def test_base_url_delegates_address_options_to_rails
    %w[http https http: https://].each do |protocol|
      options = { host: "example.com", protocol:, port: 8443 }
      Rails.application.default_url_options = options

      assert_equal ActionDispatch::Http::URL.full_url_for(options), AppUrl.base_url
    end
  end

  def test_base_url_uses_rails_effective_protocol_default
    Rails.application.default_url_options = { host: "example.com" }

    ActionDispatch::Http::URL.secure_protocol = false
    assert_equal "http://example.com", AppUrl.base_url

    ActionDispatch::Http::URL.secure_protocol = true
    assert_equal "https://example.com", AppUrl.base_url
  end

  def test_base_url_only_forwards_host_protocol_and_port
    options = {
      host: "example.com",
      protocol: "https",
      port: 443,
      path: "/private",
      params: { token: "secret" },
      anchor: "section",
      user: "username",
      password: "password",
      only_path: true
    }
    Rails.application.default_url_options = options

    assert_equal "https://example.com", AppUrl.base_url
    assert_same options, AppUrl.url_options
  end

  def test_base_url_uses_rails_port_and_ipv6_handling
    Rails.application.default_url_options = { host: "[::1]", protocol: "https", port: 4443 }
    assert_equal "https://[::1]:4443", AppUrl.base_url

    Rails.application.default_url_options = { host: "example.com", protocol: "https", port: 443 }
    assert_equal "https://example.com", AppUrl.base_url
  end

  def test_base_url_returns_nil_without_a_host
    Rails.application.default_url_options = { protocol: "https", port: 443 }

    assert_nil AppUrl.base_url
  end

  def test_base_url_leaves_invalid_protocol_errors_to_rails
    ["", "http::"].each do |protocol|
      Rails.application.default_url_options = { host: "example.com", protocol: }

      error = assert_raises(ArgumentError) { AppUrl.base_url }
      refute_kind_of AppUrl::ConfigurationError, error
      assert_match(/Invalid :protocol option/, error.message)
    end
  end

  def test_public_url_returns_nil_for_unset_or_empty_override
    assert_nil AppUrl.public_url

    ENV["TUNNEL_URL"] = ""
    assert_nil AppUrl.public_url
  end

  def test_public_url_preserves_original_valid_spelling
    ENV["TUNNEL_URL"] = "HTTPS://Example.COM:443/"

    assert_equal "HTTPS://Example.COM:443/", AppUrl.public_url
  end

  def test_public_helpers_normalize_the_same_origin
    ENV["TUNNEL_URL"] = "HTTPS://Example.COM:443/"

    assert_equal "Example.COM", AppUrl.public_host
    assert_equal({ host: "Example.COM", protocol: "https", port: 443 }, AppUrl.public_url_options)
    assert_equal "https://Example.COM", AppUrl.public_base_url
  end

  def test_public_helpers_support_ipv6_and_non_default_ports
    ENV["TUNNEL_URL"] = "http://[::1]:3000/"

    assert_equal "[::1]", AppUrl.public_host
    assert_equal({ host: "[::1]", protocol: "http", port: 3000 }, AppUrl.public_url_options)
    assert_equal "http://[::1]:3000", AppUrl.public_base_url
  end

  def test_public_helpers_fall_back_without_an_override
    options = { host: "example.com", protocol: "https", port: 8443 }
    Rails.application.default_url_options = options

    assert_equal "example.com", AppUrl.public_host
    assert_same options, AppUrl.public_url_options
    assert_equal "https://example.com:8443", AppUrl.public_base_url
  end

  def test_public_helpers_read_the_environment_on_every_call
    ENV["TUNNEL_URL"] = "https://first.example"
    assert_equal "first.example", AppUrl.public_host

    ENV["TUNNEL_URL"] = "https://second.example:4443"
    assert_equal "second.example", AppUrl.public_host
    assert_equal "https://second.example:4443", AppUrl.public_base_url

    ENV.delete("TUNNEL_URL")
    Rails.application.default_url_options = { host: "fallback.example" }
    assert_equal "fallback.example", AppUrl.public_host
  end

  PUBLIC_HELPERS.each do |helper|
    define_method("test_#{helper}_rejects_every_invalid_tunnel_category_safely") do
      INVALID_TUNNEL_URLS.each do |category, value|
        ENV["TUNNEL_URL"] = value

        error = assert_raises(AppUrl::ConfigurationError, category) { AppUrl.public_send(helper) }
        assert_match(/TUNNEL_URL/, error.message, category)
        assert_match(/expected an absolute http:\/\/ or https:\/\//, error.message, category)
        assert_nil error.cause, category
        refute_match SENTINEL_PATTERN, error.full_message, category
      end
    end
  end
end
