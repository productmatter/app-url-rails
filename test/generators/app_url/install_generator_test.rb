# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

class InstallGeneratorTest < Minitest::Test
  REPOSITORY_ROOT = File.expand_path("../../..", __dir__)
  DEVELOPMENT_RB = "config/environments/development.rb"
  MARKER = "# app-url-rails: configuration v1"
  CALL = "AppUrl.configure_development!(config)"
  GENERATOR_COMMAND = [
    RbConfig.ruby,
    "-rbundler/setup",
    "-I#{File.join(REPOSITORY_ROOT, "lib")}",
    "-e",
    <<~'RUBY'
      require "rails/generators"
      require "generators/app_url/install_generator"
      Rails::Generators.invoke("app_url:install")
    RUBY
  ].freeze

  LEGACY_WIRING = <<~'RUBY'
      # app-url-rails: dev URL + tunnel URL wiring.
      # Must run at config-time — Rails snapshots config.hosts during initialize!,
      # so adding hosts later (initializer, after_initialize) is silently ignored.
      require "uri"

      # Matches any port — tunnels/proxies expose different ports than the configured URL,
      # and an exact host:port match causes silent ActionCable rejection (broken live updates).
      app_url_origin = ->(uri) {
        %r{\A#{Regexp.escape(uri.scheme)}://#{Regexp.escape(uri.host)}(?::\d+)?\z}i
      }

      if (dev = ENV["DEV_URL"]) && !dev.empty?
        uri = URI(dev)
        config.hosts << uri.host
        opts = { host: uri.host, protocol: uri.scheme }
        opts[:port] = uri.port unless uri.port == uri.default_port
        Rails.application.default_url_options = opts
        if config.respond_to?(:action_cable)
          config.action_cable.allowed_request_origins ||= []
          config.action_cable.allowed_request_origins << app_url_origin.call(uri)
        end
      end

      if (tunnel = ENV["TUNNEL_URL"]) && !tunnel.empty?
        uri = URI(tunnel)
        config.hosts << uri.host
        if config.respond_to?(:action_cable)
          config.action_cable.allowed_request_origins ||= []
          config.action_cable.allowed_request_origins << app_url_origin.call(uri)
        end
      end
  RUBY

  def setup
    @app_root = Dir.mktmpdir("app-url-generator-")
  end

  def teardown
    FileUtils.remove_entry(@app_root)
  end

  def test_clean_install_inserts_current_format_at_start_of_configure_block
    path = development_file(<<~RUBY)
      Rails.application.configure do
        config.cache_classes = false
      end
    RUBY

    stdout, stderr, status = run_generator

    assert status.success?, failure_message(stdout, stderr, status)
    assert_equal <<~RUBY, File.binread(path)
      Rails.application.configure do
        #{MARKER}
        #{CALL}
        config.cache_classes = false
      end
    RUBY
  end

  def test_current_installation_is_unchanged_success
    path = development_file(<<~RUBY)
      Rails.application.configure do
        #{MARKER}
        #{CALL}
        config.cache_classes = false
      end
    RUBY
    original = File.binread(path)

    stdout, stderr, status = run_generator

    assert status.success?, failure_message(stdout, stderr, status)
    assert_match(/already installed/, stdout)
    assert_equal original, File.binread(path)
  end

  def test_second_run_is_a_verified_no_op
    path = development_file(<<~RUBY)
      Rails.application.configure do
        config.cache_classes = false
      end
    RUBY

    first_stdout, first_stderr, first_status = run_generator
    after_first_run = File.binread(path)
    second_stdout, second_stderr, second_status = run_generator

    assert first_status.success?, failure_message(first_stdout, first_stderr, first_status)
    assert second_status.success?, failure_message(second_stdout, second_stderr, second_status)
    assert_equal after_first_run, File.binread(path)
    assert_equal 1, File.binread(path).scan(MARKER).length
    assert_equal 1, File.binread(path).scan(CALL).length
  end

  def test_clean_install_preserves_crlf_line_endings
    path = development_file(
      "Rails.application.configure do\r\n  config.cache_classes = false\r\nend\r\n"
    )

    stdout, stderr, status = run_generator

    assert status.success?, failure_message(stdout, stderr, status)
    assert_equal(
      "Rails.application.configure do\r\n  #{MARKER}\r\n  #{CALL}\r\n" \
      "  config.cache_classes = false\r\nend\r\n",
      File.binread(path)
    )
  end

  def test_comments_mentioning_environment_and_method_do_not_count_as_installation
    path = development_file(<<~RUBY)
      Rails.application.configure do
        # DEV_URL and TUNNEL_URL used to be configured here.
        # A future installer might call AppUrl.configure_development!(config).
        config.cache_classes = false
      end
    RUBY

    stdout, stderr, status = run_generator

    assert status.success?, failure_message(stdout, stderr, status)
    contents = File.binread(path)
    assert_equal 2, contents.scan(CALL).length
    assert_includes contents, "# DEV_URL and TUNNEL_URL used to be configured here."
  end

  def test_complete_legacy_wiring_fails_with_manual_migration_and_no_change
    path = development_file("Rails.application.configure do\n#{LEGACY_WIRING}end\n")
    original = File.binread(path)

    stdout, stderr, status = run_generator

    refute status.success?, failure_message(stdout, stderr, status)
    assert_match(/Legacy app-url-rails wiring detected/, "#{stdout}\n#{stderr}")
    assert_match(/Migrate it manually once/, "#{stdout}\n#{stderr}")
    assert_equal original, File.binread(path)
  end

  def test_partial_environment_wiring_fails_and_is_unchanged
    assert_failure_without_change(<<~RUBY, /partial, custom, or misplaced/)
      Rails.application.configure do
        if ENV["DEV_URL"]
          config.hosts << "example.test"
        end
      end
    RUBY
  end

  def test_custom_env_fetch_wiring_fails_and_is_unchanged
    assert_failure_without_change(<<~RUBY, /partial, custom, or misplaced/)
      Rails.application.configure do
        host = ENV.fetch("DEV_URL", nil)
        tunnel = ENV.fetch "TUNNEL_URL"
      end
    RUBY
  end

  def test_setup_call_without_marker_fails_and_is_unchanged
    assert_failure_without_change(<<~RUBY, /partial, custom, or misplaced/)
      Rails.application.configure do
        #{CALL}
      end
    RUBY
  end

  def test_no_parentheses_setup_call_fails_and_is_unchanged
    assert_failure_without_change(<<~RUBY, /partial, custom, or misplaced/)
      Rails.application.configure do
        AppUrl.configure_development! config
      end
    RUBY
  end

  def test_top_level_qualified_setup_call_fails_and_is_unchanged
    assert_failure_without_change(<<~RUBY, /partial, custom, or misplaced/)
      Rails.application.configure do
        ::AppUrl.configure_development!(config)
      end
    RUBY
  end

  def test_nested_setup_call_does_not_count_as_current_installation
    assert_failure_without_change(<<~RUBY, /partial, custom, or misplaced/)
      Rails.application.configure do
        if false
          #{MARKER}
          #{CALL}
        end
      end
    RUBY
  end

  def test_known_marker_and_call_outside_configure_block_fail
    assert_failure_without_change(<<~RUBY, /partial, custom, or misplaced/)
      #{MARKER}
      #{CALL}
      Rails.application.configure do
        config.cache_classes = false
      end
    RUBY
  end

  def test_misplaced_marker_with_in_block_call_fails
    assert_failure_without_change(<<~RUBY, /partial, custom, or misplaced/)
      #{MARKER}
      Rails.application.configure do
        #{CALL}
      end
    RUBY
  end

  def test_unknown_format_marker_fails_and_is_unchanged
    assert_failure_without_change(<<~RUBY, /unsupported app-url-rails configuration marker/)
      Rails.application.configure do
        # app-url-rails: configuration v2
        #{CALL}
      end
    RUBY
  end

  def test_missing_development_file_exits_nonzero_without_creating_it
    stdout, stderr, status = run_generator

    refute status.success?, failure_message(stdout, stderr, status)
    assert_match(/development\.rb not found/, "#{stdout}\n#{stderr}")
    refute File.exist?(File.join(@app_root, DEVELOPMENT_RB))
  end

  def test_unsupported_configure_block_shape_fails_and_is_unchanged
    assert_failure_without_change(<<~RUBY, /standard `Rails\.application\.configure do` block/)
      Rails.application.configure {
        config.cache_classes = false
      }
    RUBY
  end

  def test_nested_standard_configure_block_fails_and_is_unchanged
    assert_failure_without_change(<<~RUBY, /standard `Rails\.application\.configure do` block/)
      if ENV["WRAP_CONFIG"]
        Rails.application.configure do
          config.cache_classes = false
        end
      end
    RUBY
  end

  def test_invalid_ruby_fails_and_is_unchanged
    assert_failure_without_change(<<~RUBY, /not valid Ruby/)
      Rails.application.configure do
        config.cache_classes =
      end
    RUBY
  end

  private

  def development_file(contents)
    path = File.join(@app_root, DEVELOPMENT_RB)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, contents)
    path
  end

  def run_generator
    Open3.capture3(*GENERATOR_COMMAND, chdir: @app_root)
  end

  def assert_failure_without_change(contents, message_pattern)
    path = development_file(contents)
    original = File.binread(path)

    stdout, stderr, status = run_generator

    refute status.success?, failure_message(stdout, stderr, status)
    assert_match message_pattern, "#{stdout}\n#{stderr}"
    assert_equal original, File.binread(path)
  end

  def failure_message(stdout, stderr, status)
    "generator exited #{status.exitstatus}\nstdout:\n#{stdout}\nstderr:\n#{stderr}"
  end
end
