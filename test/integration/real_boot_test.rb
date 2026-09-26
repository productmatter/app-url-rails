# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../support/real_boot_app"

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

  private

  def boot(dev_url:, tunnel_url:, with_action_cable:)
    Dir.mktmpdir("app-url-real-boot") do |root|
      RealBootApp.build(root)
      return RealBootApp.boot(root, dev_url:, tunnel_url:, with_action_cable:)
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

    assert_equal 200, statuses.fetch("preserved.example")
    assert_equal(dev_url ? 200 : 403, statuses.fetch("dev.example"))
    assert_equal(tunnel_url ? 200 : 403, statuses.fetch("tunnel.example"))
    assert_equal 403, statuses.fetch("unrelated.example")
  end

  def assert_cable_origins(result, dev_url:, tunnel_url:)
    origins = result.fetch("cable_origins")

    assert origins.fetch("preserved")
    assert_equal !!dev_url, origins.fetch("dev")
    refute origins.fetch("dev_wrong_scheme")
    refute origins.fetch("dev_lookalike")
    assert_equal !!tunnel_url, origins.fetch("tunnel")
    refute origins.fetch("tunnel_wrong_scheme")
    refute origins.fetch("tunnel_lookalike")
    refute origins.fetch("unrelated")
  end
end
