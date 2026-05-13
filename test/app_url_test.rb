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
  def setup
    @saved_tunnel_url = ENV["TUNNEL_URL"]
    ENV.delete("TUNNEL_URL")
    Rails.application = FakeApplication.new
  end

  def teardown
    @saved_tunnel_url.nil? ? ENV.delete("TUNNEL_URL") : ENV["TUNNEL_URL"] = @saved_tunnel_url
    Rails.application = nil
  end

  # host — the app's host (default_url_options[:host])

  def test_host_returns_default_url_options_host
    Rails.application.default_url_options = { host: "example.com" }
    assert_equal "example.com", AppUrl.host
  end

  def test_host_returns_nil_when_default_url_options_empty
    assert_nil AppUrl.host
  end

  def test_host_ignores_tunnel_url
    ENV["TUNNEL_URL"] = "https://abc.ngrok-free.app"
    Rails.application.default_url_options = { host: "localhost" }
    assert_equal "localhost", AppUrl.host
  end

  # url_options — passthrough to default_url_options

  def test_url_options_returns_default_url_options
    Rails.application.default_url_options = { host: "example.com", protocol: "https" }
    assert_equal({ host: "example.com", protocol: "https" }, AppUrl.url_options)
  end

  def test_url_options_ignores_tunnel_url
    ENV["TUNNEL_URL"] = "https://abc.ngrok-free.app"
    Rails.application.default_url_options = { host: "localhost", protocol: "http", port: 3000 }
    assert_equal({ host: "localhost", protocol: "http", port: 3000 }, AppUrl.url_options)
  end

  # base_url

  def test_base_url_assembles_from_default_url_options
    Rails.application.default_url_options = { host: "example.com", protocol: "https" }
    assert_equal "https://example.com", AppUrl.base_url
  end

  def test_base_url_defaults_protocol_to_https
    Rails.application.default_url_options = { host: "example.com" }
    assert_equal "https://example.com", AppUrl.base_url
  end

  def test_base_url_includes_non_default_port
    Rails.application.default_url_options = { host: "localhost", protocol: "http", port: 3000 }
    assert_equal "http://localhost:3000", AppUrl.base_url
  end

  def test_base_url_omits_default_port
    Rails.application.default_url_options = { host: "example.com", protocol: "https", port: 443 }
    assert_equal "https://example.com", AppUrl.base_url
  end

  def test_base_url_returns_nil_when_host_missing
    assert_nil AppUrl.base_url
  end

  # public_url — raw TUNNEL_URL

  def test_public_url_returns_nil_when_env_unset
    assert_nil AppUrl.public_url
  end

  def test_public_url_returns_nil_when_env_empty
    ENV["TUNNEL_URL"] = ""
    assert_nil AppUrl.public_url
  end

  def test_public_url_returns_value_when_env_set
    ENV["TUNNEL_URL"] = "https://abc.ngrok-free.app"
    assert_equal "https://abc.ngrok-free.app", AppUrl.public_url
  end

  # public_host

  def test_public_host_returns_tunnel_host_when_set
    ENV["TUNNEL_URL"] = "https://abc.ngrok-free.app/some/path"
    assert_equal "abc.ngrok-free.app", AppUrl.public_host
  end

  def test_public_host_falls_back_to_host_when_tunnel_unset
    Rails.application.default_url_options = { host: "example.com" }
    assert_equal "example.com", AppUrl.public_host
  end

  def test_public_host_returns_nil_when_neither_set
    assert_nil AppUrl.public_host
  end

  # public_url_options

  def test_public_url_options_falls_back_to_url_options_when_tunnel_unset
    Rails.application.default_url_options = { host: "localhost", protocol: "http", port: 3000 }
    assert_equal({ host: "localhost", protocol: "http", port: 3000 }, AppUrl.public_url_options)
  end

  def test_public_url_options_uses_tunnel_when_set
    ENV["TUNNEL_URL"] = "https://abc.ngrok-free.app"
    Rails.application.default_url_options = { host: "localhost", protocol: "http", port: 3000 }
    assert_equal({ host: "abc.ngrok-free.app", protocol: "https" }, AppUrl.public_url_options)
  end

  def test_public_url_options_includes_non_default_port_from_tunnel
    ENV["TUNNEL_URL"] = "http://abc.example.com:8080"
    assert_equal({ host: "abc.example.com", protocol: "http", port: 8080 }, AppUrl.public_url_options)
  end

  def test_public_url_options_omits_default_port_from_tunnel
    ENV["TUNNEL_URL"] = "https://abc.example.com:443"
    refute_includes AppUrl.public_url_options, :port
  end

  # public_base_url

  def test_public_base_url_returns_tunnel_when_set
    ENV["TUNNEL_URL"] = "https://abc.ngrok-free.app"
    assert_equal "https://abc.ngrok-free.app", AppUrl.public_base_url
  end

  def test_public_base_url_falls_back_to_base_url_when_tunnel_unset
    Rails.application.default_url_options = { host: "example.com", protocol: "https" }
    assert_equal "https://example.com", AppUrl.public_base_url
  end

  def test_public_base_url_returns_nil_when_neither_set
    assert_nil AppUrl.public_base_url
  end
end
