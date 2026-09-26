# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require_relative "../lib/app_url/version"

class RequireTest < Minitest::Test
  %w[app-url-rails app_url_rails app_url].each do |entry_point|
    define_method("test_require_#{entry_point}") do
      stdout, stderr, status = Open3.capture3(
        { "TUNNEL_URL" => "https://tunnel.example:443/" },
        RbConfig.ruby, "-I#{File.expand_path('../lib', __dir__)}", "-r", entry_point,
        "-e", 'puts AppUrl::VERSION; puts AppUrl.public_base_url'
      )

      assert_equal 0, status.exitstatus, stderr
      assert_equal "#{AppUrl::VERSION}\nhttps://tunnel.example\n", stdout
    end
  end
end
