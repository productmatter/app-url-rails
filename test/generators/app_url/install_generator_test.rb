# frozen_string_literal: true

require "minitest/autorun"
require "rails/generators"
require "rails/generators/test_case"
require_relative "../../../lib/generators/app_url/install_generator"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests AppUrl::Generators::InstallGenerator
  destination File.expand_path("../../tmp/generator", __dir__)

  setup :prepare_destination

  def write_development_rb(body)
    FileUtils.mkdir_p(File.join(destination_root, "config/environments"))
    File.write(File.join(destination_root, "config/environments/development.rb"), body)
  end

  def read_development_rb
    File.read(File.join(destination_root, "config/environments/development.rb"))
  end

  # The generator reads/writes config/environments/development.rb via relative
  # path, expecting to be run from the Rails app root. Mirror that for tests.
  def run_generator(args = [])
    Dir.chdir(destination_root) { super }
  end

  def test_generator_is_discoverable_by_rails_generators_lookup
    Rails::Generators.invoke("app_url:install", [], destination_root: destination_root)
    refute_nil Rails::Generators.find_by_namespace("app_url:install"),
               "Rails should find the generator at lib/generators/app_url/install_generator.rb"
  end

  def test_injects_wiring_into_configure_block
    write_development_rb(<<~RUBY)
      Rails.application.configure do
        config.cache_classes = false
      end
    RUBY

    run_generator

    contents = read_development_rb
    assert_includes contents, "app-url-rails: dev URL + tunnel URL wiring."
    assert_includes contents, 'ENV["DEV_URL"]'
    assert_includes contents, 'ENV["TUNNEL_URL"]'
  end

  def test_wires_action_cable_allowed_request_origins
    write_development_rb(<<~RUBY)
      Rails.application.configure do
        config.cache_classes = false
      end
    RUBY

    run_generator

    contents = read_development_rb
    assert_includes contents, "config.action_cable.allowed_request_origins",
                    "wiring must extend Action Cable's allowed origins for DEV_URL/TUNNEL_URL"
    assert_includes contents, "config.respond_to?(:action_cable)",
                    "cable wiring must be guarded for apps without Action Cable loaded"
  end

  def test_origin_helper_includes_non_default_port_in_emitted_wiring
    wiring = AppUrl::Generators::InstallGenerator::WIRING
    # The lambda must conditionally append :port — bare host won't match the
    # Origin header a browser sends from http://localhost:3000.
    assert_includes wiring, "uri.port != uri.default_port",
                    "origin helper must distinguish default from non-default ports"
    assert_match(/:\#\{uri\.port\}/, wiring,
                 "origin helper must interpolate the port when non-default")
  end

  def test_injected_block_is_indented_inside_configure
    write_development_rb(<<~RUBY)
      Rails.application.configure do
        config.cache_classes = false
      end
    RUBY

    run_generator

    contents = read_development_rb
    assert_match(/^  # app-url-rails:/, contents,
                 "wiring should be indented two spaces to sit inside the configure block")
    assert_match(/^  require "uri"/, contents)
  end

  def test_injects_directly_after_configure_opener
    write_development_rb(<<~RUBY)
      Rails.application.configure do
        config.cache_classes = false
      end
    RUBY

    run_generator

    contents = read_development_rb
    configure_index = contents.index("Rails.application.configure do")
    wiring_index = contents.index("app-url-rails:")
    existing_config_index = contents.index("config.cache_classes")
    assert wiring_index > configure_index, "wiring must be inside the configure block"
    assert wiring_index < existing_config_index, "wiring must precede existing config so it runs at config-time"
  end

  def test_idempotent_when_dev_url_already_referenced
    original = <<~RUBY
      Rails.application.configure do
        # already wired: uses ENV["DEV_URL"]
      end
    RUBY
    write_development_rb(original)

    run_generator

    assert_equal original, read_development_rb,
                 "generator should skip files already referencing DEV_URL"
  end

  def test_idempotent_when_tunnel_url_already_referenced
    original = <<~RUBY
      Rails.application.configure do
        # already wired: uses ENV["TUNNEL_URL"]
      end
    RUBY
    write_development_rb(original)

    run_generator

    assert_equal original, read_development_rb,
                 "generator should skip files already referencing TUNNEL_URL"
  end

  def test_safe_to_rerun
    write_development_rb(<<~RUBY)
      Rails.application.configure do
        config.cache_classes = false
      end
    RUBY

    run_generator
    after_first_run = read_development_rb
    run_generator
    after_second_run = read_development_rb

    assert_equal after_first_run, after_second_run,
                 "running twice should be a no-op on the second invocation"
  end

  def test_does_not_crash_or_create_files_when_development_rb_missing
    refute File.exist?(File.join(destination_root, "config/environments/development.rb"))
    capture(:stderr) { capture(:stdout) { run_generator } }
    refute File.exist?(File.join(destination_root, "config/environments/development.rb")),
           "generator must not create development.rb on its own"
  end
end
