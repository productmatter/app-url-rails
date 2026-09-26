# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../support/real_boot_app"
require_relative "../support/app_url_test_support"

class RealBootTest < Minitest::Test
  SCENARIOS = {
    "neither URL" => [nil, nil],
    "DEV_URL only" => ["http://dev.example:3100", nil],
    "TUNNEL_URL only" => [nil, "https://tunnel.example:4443"],
    "both URLs" => ["http://dev.example:3100", "https://tunnel.example:4443"]
  }.freeze

  SCENARIOS.each do |name, (dev_url, tunnel_url)|
    [false, true].each do |with_action_cable|
      define_method("test_real_boot_with_#{name}_and_cable_#{with_action_cable}") do
        result = boot(dev_url:, tunnel_url:, with_action_cable:)

        assert_addresses(result, dev_url:, tunnel_url:)
        assert_host_authorization(result, dev_url:, tunnel_url:)
        assert_cable_origins(result, dev_url:, tunnel_url:) if with_action_cable
        refute result.key?("cable_origins") unless with_action_cable
      end
    end
  end

  def test_default_dev_port_replaces_a_stale_non_default_port
    result = boot(dev_url: "https://dev.example:443/", tunnel_url: nil, with_action_cable: false)

    assert_equal({ "host" => "dev.example", "protocol" => "https" }, result.fetch("url_options"))
    assert_equal "https://dev.example", result.fetch("base_url")
    assert_equal "https://dev.example/probe", result.fetch("route_url")
  end

  def test_repeated_setup_does_not_duplicate_hosts_or_cable_origins
    result = boot(
      dev_url: "http://dev.example:3100",
      tunnel_url: "https://tunnel.example:4443",
      with_action_cable: true,
      build_options: { repeat_setup: true }
    )

    assert_equal({ "preserved.example" => 1, "dev.example" => 1, "tunnel.example" => 1 },
                 result.fetch("host_counts"))
    assert_equal 3, result.fetch("cable_origin_count")
    assert_addresses(result, dev_url: "http://dev.example:3100",
                      tunnel_url: "https://tunnel.example:4443")
  end

  def test_setup_preserves_rails_default_localhost_cable_allowance_only_in_development
    %w[development test].each do |rails_env|
      result = boot(
        dev_url: "http://dev.example:3100", tunnel_url: nil,
        with_action_cable: true, cable_origins: nil, rails_env:,
        build_options: { repeat_setup: true }
      )

      assert_equal rails_env == "development", result.fetch("cable_origins").fetch("localhost")
      assert result.fetch("cable_origins").fetch("dev")
      refute result.fetch("cable_origins").fetch("unrelated")
      assert_equal rails_env == "development" ? 2 : 1, result.fetch("cable_origin_count")
    end
  end

  def test_setup_respects_explicit_empty_cable_allowances
    result = boot(
      dev_url: "http://dev.example:3100", tunnel_url: nil,
      with_action_cable: true, cable_origins: :empty
    )

    refute result.fetch("cable_origins").fetch("localhost")
    assert result.fetch("cable_origins").fetch("dev")
    assert_equal 1, result.fetch("cable_origin_count")
  end

  def test_no_environment_urls_leave_rails_default_cable_allowance_intact
    result = boot(dev_url: nil, tunnel_url: nil, with_action_cable: true, cable_origins: nil)

    assert result.fetch("cable_origins").fetch("localhost")
    refute result.fetch("cable_origins").fetch("dev")
    assert_equal 1, result.fetch("cable_origin_count")
  end

  def test_explicit_setup_has_the_same_effect_in_test_environment
    result = boot(
      dev_url: "http://dev.example:3100",
      tunnel_url: "https://tunnel.example:4443",
      with_action_cable: true,
      rails_env: "test"
    )

    assert_addresses(result, dev_url: "http://dev.example:3100",
                      tunnel_url: "https://tunnel.example:4443")
    assert_host_authorization(result, dev_url: true, tunnel_url: true)
    assert_cable_origins(result, dev_url: true, tunnel_url: true)
  end

  def test_omitted_protocol_follows_rails_force_ssl_setting
    without_ssl = boot(
      dev_url: nil,
      tunnel_url: nil,
      with_action_cable: false,
      omit_protocol: true
    )
    with_ssl = boot(
      dev_url: nil,
      tunnel_url: nil,
      with_action_cable: false,
      omit_protocol: true,
      force_ssl: true
    )

    assert_equal "http://preserved.example:4444", without_ssl.fetch("base_url")
    assert_equal "http://preserved.example:4444/probe", without_ssl.fetch("route_url")
    assert_equal "https://preserved.example:4444", with_ssl.fetch("base_url")
    assert_equal "https://preserved.example:4444/probe", with_ssl.fetch("route_url")
  end

  def test_invalid_tunnel_is_reported_before_valid_dev_url_mutates_boot_configuration
    result = boot(
      dev_url: "http://dev.example:3100",
      tunnel_url: "https://user:secret-sentinel@tunnel.example",
      with_action_cable: true,
      build_options: { capture_setup_error: true }
    )

    error = result.fetch("setup_error")
    assert_equal "AppUrl::ConfigurationError", error.fetch("class")
    assert_match(/TUNNEL_URL.*userinfo/, error.fetch("message"))
    refute_includes error.fetch("message"), "secret-sentinel"
    assert_nil error.fetch("cause")
    assert_equal({ "host" => "preserved.example", "protocol" => "https", "port" => 4444 },
                 result.fetch("url_options"))
    assert_equal({ "preserved.example" => 1, "dev.example" => 0, "tunnel.example" => 0 },
                 result.fetch("host_counts"))
    assert_equal 1, result.fetch("cable_origin_count")
    assert_equal 403, result.fetch("host_statuses").fetch("dev.example")
    assert_equal 403, result.fetch("host_statuses").fetch("tunnel.example")
  end

  def test_explicit_protocol_and_dev_url_override_force_ssl_for_generated_addresses
    [false, true].each do |force_ssl|
      explicit = boot(
        dev_url: nil, tunnel_url: nil, with_action_cable: false,
        protocol: "http:", force_ssl:
      )
      development = boot(
        dev_url: "http://dev.example:3100", tunnel_url: nil,
        with_action_cable: false, force_ssl:
      )

      assert_equal "http://preserved.example:4444", explicit.fetch("base_url")
      assert_equal "http://preserved.example:4444/probe", explicit.fetch("route_url")
      assert_equal "http://dev.example:3100", development.fetch("base_url")
      assert_equal "http://dev.example:3100/probe", development.fetch("route_url")
    end
  end

  def test_invalid_dev_url_aborts_boot_without_echoing_its_value
    Dir.mktmpdir("app-url-real-boot") do |root|
      RealBootApp.build(root)
      stdout, stderr, status = RealBootApp.boot_process(
        root, dev_url: "https://user:secret-sentinel@dev.example",
        tunnel_url: nil, with_action_cable: true
      )

      refute status.success?
      assert_match(/AppUrl::ConfigurationError/, stderr)
      assert_match(/DEV_URL.*userinfo/, stderr)
      refute_includes stdout + stderr, "secret-sentinel"
    end
  end

  def test_later_explicit_app_settings_override_the_setup_call
    result = boot(
      dev_url: "http://dev.example:3100", tunnel_url: nil,
      with_action_cable: false, build_options: { later_defaults: true }
    )

    assert_equal({ "host" => "later.example", "protocol" => "https", "port" => 8443 },
                 result.fetch("url_options"))
    assert_equal "https://later.example:8443", result.fetch("base_url")
    assert_equal "https://later.example:8443/probe", result.fetch("route_url")
    assert_equal 200, result.fetch("host_statuses").fetch("dev.example")
  end

  def test_manual_legacy_replacement_with_the_marker_and_setup_call_boots
    result = Dir.mktmpdir("app-url-real-boot") do |root|
      RealBootApp.build(root, installation: :manual)
      development_rb = File.read(File.join(root, "config/environments/development.rb"))
      refute_includes development_rb, "dev URL + tunnel URL wiring"
      refute_includes development_rb, "app_url_origin"
      refute_includes development_rb, 'ENV["DEV_URL"]'
      assert_includes development_rb, "# app-url-rails: configuration v1"
      assert_includes development_rb, "AppUrl.configure_development!(config)"
      assert_includes development_rb, "config.consider_all_requests_local = false"

      RealBootApp.boot(
        root,
        dev_url: "http://dev.example:3100",
        tunnel_url: "https://tunnel.example:4443",
        with_action_cable: true
      )
    end

    assert_addresses(result, dev_url: "http://dev.example:3100",
                      tunnel_url: "https://tunnel.example:4443")
    assert_host_authorization(result, dev_url: true, tunnel_url: true)
    assert_cable_origins(result, dev_url: true, tunnel_url: true)
  end

  def test_public_helpers_validate_direct_access_without_installation_outside_development
    results = boot(
      dev_url: nil, tunnel_url: nil, with_action_cable: false, rails_env: "test",
      public_helper: :invalid_grid, build_options: { installation: :none }
    )

    %w[public_url public_host public_url_options public_base_url].each do |helper|
      AppUrlTestSupport::INVALID_ENVIRONMENT_URLS.each do |category, (value, reason)|
        error = results.fetch(helper).fetch(category).fetch("error")
        context = "#{helper}: #{category}"
        assert_equal "AppUrl::ConfigurationError", error.fetch("class"), context
        assert_match(/\ATUNNEL_URL #{Regexp.escape(reason)};/, error.fetch("message"), context)
        assert_match(/expected an absolute http:\/\/ or https:\/\//, error.fetch("message"), context)
        sentinel = value.b[/[a-z]+-sentinel/]
        refute_includes error.fetch("message"), sentinel, context if sentinel
        assert_nil error.fetch("cause"), context
      end
    end
  end

  def test_setup_preserves_action_mailer_defaults
    result = boot(
      dev_url: "http://dev.example:3100", tunnel_url: "https://tunnel.example:4443",
      with_action_cable: false, with_action_mailer: true
    )

    assert_equal({ "host" => "mail.example", "protocol" => "https", "port" => 8443 },
                 result.fetch("mailer_url_options"))
    assert_addresses(result, dev_url: "http://dev.example:3100",
                      tunnel_url: "https://tunnel.example:4443")
  end

  def test_requiring_the_gem_without_installation_leaves_configuration_untouched
    %w[development test].each do |rails_env|
      result = boot(
        dev_url: "http://dev.example:3100", tunnel_url: "https://tunnel.example:4443",
        with_action_cable: true, rails_env:, build_options: { installation: :none }
      )

      assert_addresses(result, dev_url: nil, tunnel_url: "https://tunnel.example:4443")
      assert_host_authorization(result, dev_url: nil, tunnel_url: nil)
      assert_cable_origins(result, dev_url: nil, tunnel_url: nil)
    end
  end

  def test_dev_setup_preserves_unrelated_defaults_but_base_url_uses_only_address_options
    result = boot(
      dev_url: "http://dev.example:3100",
      tunnel_url: nil,
      with_action_cable: false,
      extra_default: true
    )

    assert_equal({ "host" => "dev.example", "protocol" => "http", "port" => 3100,
                   "locale" => "en" }, result.fetch("url_options"))
    assert_equal "http://dev.example:3100", result.fetch("base_url")
    assert_equal "http://dev.example:3100/probe?locale=en", result.fetch("route_url")
  end

  def test_public_default_port_overrides_the_dev_port_in_real_route_generation
    result = boot(
      dev_url: "http://dev.example:3100",
      tunnel_url: "https://tunnel.example:443/",
      with_action_cable: false
    )

    assert_equal({ "host" => "tunnel.example", "protocol" => "https", "port" => 443 },
                 result.fetch("public_url_options"))
    assert_equal "https://tunnel.example", result.fetch("public_base_url")
    assert_equal "https://tunnel.example/probe", result.fetch("public_route_url")
  end

  private

  def boot(dev_url:, tunnel_url:, with_action_cable:, build_options: {}, **boot_options)
    Dir.mktmpdir("app-url-real-boot") do |root|
      RealBootApp.build(root, **build_options)
      return RealBootApp.boot(root, dev_url:, tunnel_url:, with_action_cable:, **boot_options)
    end
  end

  def assert_addresses(result, dev_url:, tunnel_url:)
    expected_options = if dev_url
                         { "host" => "dev.example", "protocol" => "http", "port" => 3100 }
                       else
                         { "host" => "preserved.example", "protocol" => "https", "port" => 4444 }
                       end
    expected_base_url = dev_url || "https://preserved.example:4444"

    assert_equal expected_options, result.fetch("url_options")
    assert_equal expected_base_url, result.fetch("base_url")
    assert_equal "#{expected_base_url}/probe", result.fetch("route_url")
    assert_equal "#{tunnel_url || expected_base_url}/probe", result.fetch("public_route_url")

    if tunnel_url
      assert_equal tunnel_url, result.fetch("public_url")
      assert_equal "tunnel.example", result.fetch("public_host")
      assert_equal({ "host" => "tunnel.example", "protocol" => "https", "port" => 4443 },
                   result.fetch("public_url_options"))
      assert_equal tunnel_url, result.fetch("public_base_url")
    else
      assert_nil result.fetch("public_url")
      assert_equal expected_options.fetch("host"), result.fetch("public_host")
      assert_equal expected_options, result.fetch("public_url_options")
      assert_equal expected_base_url, result.fetch("public_base_url")
    end
  end

  def assert_host_authorization(result, dev_url:, tunnel_url:)
    statuses = result.fetch("host_statuses")
    counts = result.fetch("host_counts")

    assert_equal 200, statuses.fetch("preserved.example")
    assert_equal(dev_url ? 200 : 403, statuses.fetch("dev.example"))
    assert_equal(tunnel_url ? 200 : 403, statuses.fetch("tunnel.example"))
    assert_equal 403, statuses.fetch("unrelated.example")
    %w[dev.example.evil notdev.example tunnel.example.evil nottunnel.example].each do |host|
      assert_equal 403, statuses.fetch(host), host
    end
    assert_equal 1, counts.fetch("preserved.example")
    assert_equal(dev_url ? 1 : 0, counts.fetch("dev.example"))
    assert_equal(tunnel_url ? 1 : 0, counts.fetch("tunnel.example"))
  end

  def assert_cable_origins(result, dev_url:, tunnel_url:)
    origins = result.fetch("cable_origins")

    assert origins.fetch("preserved")
    refute origins.fetch("localhost")
    assert_equal !!dev_url, origins.fetch("dev")
    refute origins.fetch("dev_wrong_scheme")
    refute origins.fetch("dev_lookalike")
    assert_equal !!tunnel_url, origins.fetch("tunnel")
    refute origins.fetch("tunnel_wrong_scheme")
    refute origins.fetch("tunnel_lookalike")
    refute origins.fetch("unrelated")
    assert_equal 1 + (dev_url ? 1 : 0) + (tunnel_url ? 1 : 0), result.fetch("cable_origin_count")
  end
end
