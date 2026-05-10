# frozen_string_literal: true

require "minitest/autorun"
require "minitest/mock"

require_relative "../lib/git/treeline/rails/gtl_adapter"
require_relative "../lib/git/treeline/rails/tunnel_url"

class TunnelUrlTest < Minitest::Test
  TunnelUrl = Git::Treeline::Rails::TunnelUrl
  GtlAdapter = Git::Treeline::Rails::GtlAdapter

  TRACKED_ENV = %w[TUNNEL_PROVIDER NGROK_URL DEV_ACCESS_URL].freeze

  def setup
    @saved_env = TRACKED_ENV.to_h { |k| [k, ENV[k]] }
    TRACKED_ENV.each { |k| ENV.delete(k) }
    TunnelUrl.reset!
  end

  def teardown
    @saved_env.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    TunnelUrl.reset!
  end

  def test_returns_nil_for_provider_none
    ENV["TUNNEL_PROVIDER"] = "none"
    assert_nil TunnelUrl.url
  end

  def test_defaults_to_none_when_provider_unset
    assert_nil TunnelUrl.url
  end

  def test_returns_ngrok_url_for_provider_ngrok
    ENV["TUNNEL_PROVIDER"] = "ngrok"
    ENV["NGROK_URL"] = "https://abc.ngrok-free.app"
    assert_equal "https://abc.ngrok-free.app", TunnelUrl.url
  end

  def test_raises_when_ngrok_provider_without_url
    ENV["TUNNEL_PROVIDER"] = "ngrok"
    assert_raises(KeyError) { TunnelUrl.url }
  end

  def test_invokes_gtl_adapter_for_provider_gtl
    ENV["TUNNEL_PROVIDER"] = "gtl"
    GtlAdapter.stub :tunnel_url, "https://feature.gtltunnel.dev" do
      assert_equal "https://feature.gtltunnel.dev", TunnelUrl.url
    end
  end

  def test_caches_url_across_calls
    counter = 0
    TunnelUrl.register("counter_provider") do
      counter += 1
      "https://test.example.com"
    end
    ENV["TUNNEL_PROVIDER"] = "counter_provider"
    3.times { TunnelUrl.url }
    assert_equal 1, counter
  ensure
    TunnelUrl.providers.delete("counter_provider")
  end

  def test_caches_nil_result
    counter = 0
    TunnelUrl.register("nil_counter") do
      counter += 1
      nil
    end
    ENV["TUNNEL_PROVIDER"] = "nil_counter"
    3.times { TunnelUrl.url }
    assert_equal 1, counter
  ensure
    TunnelUrl.providers.delete("nil_counter")
  end

  def test_reset_clears_cache
    counter = 0
    TunnelUrl.register("reset_counter") do
      counter += 1
      "https://test.example.com"
    end
    ENV["TUNNEL_PROVIDER"] = "reset_counter"
    TunnelUrl.url
    TunnelUrl.reset!
    TunnelUrl.url
    assert_equal 2, counter
  ensure
    TunnelUrl.providers.delete("reset_counter")
  end

  def test_host_returns_nil_when_no_tunnel
    ENV["TUNNEL_PROVIDER"] = "none"
    assert_nil TunnelUrl.host
  end

  def test_host_extracts_host_from_tunnel_url
    ENV["TUNNEL_PROVIDER"] = "ngrok"
    ENV["NGROK_URL"] = "https://abc.ngrok-free.app"
    assert_equal "abc.ngrok-free.app", TunnelUrl.host
  end

  def test_public_url_options_uses_tunnel_when_present
    ENV["TUNNEL_PROVIDER"] = "ngrok"
    ENV["NGROK_URL"] = "https://abc.ngrok-free.app"
    opts = TunnelUrl.public_url_options
    assert_equal({ host: "abc.ngrok-free.app", protocol: "https" }, opts)
  end

  def test_public_url_options_includes_non_default_port
    ENV["TUNNEL_PROVIDER"] = "ngrok"
    ENV["NGROK_URL"] = "http://abc.ngrok-free.app:8080"
    opts = TunnelUrl.public_url_options
    assert_equal 8080, opts[:port]
  end

  def test_public_url_options_omits_default_port
    ENV["TUNNEL_PROVIDER"] = "ngrok"
    ENV["NGROK_URL"] = "https://abc.ngrok-free.app:443"
    opts = TunnelUrl.public_url_options
    refute_includes opts, :port
  end

  def test_public_url_options_falls_back_to_dev_access_url
    ENV["TUNNEL_PROVIDER"] = "none"
    ENV["DEV_ACCESS_URL"] = "http://localhost:3000"
    opts = TunnelUrl.public_url_options
    assert_equal({ host: "localhost", protocol: "http", port: 3000 }, opts)
  end

  def test_public_url_options_raises_without_fallback
    ENV["TUNNEL_PROVIDER"] = "none"
    assert_raises(KeyError) { TunnelUrl.public_url_options }
  end

  def test_public_base_url_returns_tunnel_when_present
    ENV["TUNNEL_PROVIDER"] = "ngrok"
    ENV["NGROK_URL"] = "https://abc.ngrok-free.app"
    assert_equal "https://abc.ngrok-free.app", TunnelUrl.public_base_url
  end

  def test_public_base_url_falls_back_to_dev_access_url
    ENV["TUNNEL_PROVIDER"] = "none"
    ENV["DEV_ACCESS_URL"] = "http://localhost:3000"
    assert_equal "http://localhost:3000", TunnelUrl.public_base_url
  end

  def test_register_supports_custom_providers
    TunnelUrl.register(:my_custom) { "https://custom.example.com" }
    ENV["TUNNEL_PROVIDER"] = "my_custom"
    assert_equal "https://custom.example.com", TunnelUrl.url
  ensure
    TunnelUrl.providers.delete("my_custom")
  end

  def test_register_normalizes_symbol_and_string_names
    TunnelUrl.register(:sym_provider) { "from-symbol" }
    assert TunnelUrl.providers.key?("sym_provider")
  ensure
    TunnelUrl.providers.delete("sym_provider")
  end

  def test_register_requires_block
    assert_raises(ArgumentError) { TunnelUrl.register(:no_block) }
  end

  def test_unknown_provider_raises_with_helpful_message
    ENV["TUNNEL_PROVIDER"] = "bogus_provider_xyz"
    err = assert_raises(ArgumentError) { TunnelUrl.url }
    assert_match(/bogus_provider_xyz/, err.message)
    assert_match(/Registered providers/, err.message)
  end
end
