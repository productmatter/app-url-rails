# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "yaml"
require "fileutils"
require "open3"
require "json"

class WiringIntegrationTest < Minitest::Test
  def boot_and_dump(env: {}, app_config: "", rails_env: "development",
                    treeline_yml: nil, env_local: nil, extra_files: {})
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".treeline.yml"), YAML.dump(treeline_yml)) if treeline_yml
      File.write(File.join(dir, ".env.local"), env_local) if env_local
      extra_files.each do |name, content|
        path = File.join(dir, name)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end

      boot_script = <<~RUBY
        require "rails"
        require "action_mailer/railtie"
        require "git/treeline/rails"

        ENV["RAILS_ENV"] = #{rails_env.inspect}

        module TreelineTestApp
          class Application < Rails::Application
            config.eager_load = false
            config.logger = Logger.new(File::NULL)
            config.session_store :cookie_store, key: "_test_session"
            #{app_config}
          end
        end

        Rails.application.initialize!

        dump = {
          hosts: Rails.application.config.hosts.map(&:to_s),
          default_url_options: Rails.application.default_url_options,
          mailer_url_options: ActionMailer::Base.default_url_options,
          session_options: Rails.application.config.session_options
        }
        STDOUT.puts "DUMP:" + JSON.dump(dump)
      RUBY

      env = env.merge("BUNDLE_GEMFILE" => File.join(__dir__, "..", "Gemfile"))
      stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "ruby", "-e", boot_script, chdir: dir)
      assert status.success?, "Rails boot failed:\nstdout: #{stdout}\nstderr: #{stderr}"

      line = stdout.lines.find { |l| l.start_with?("DUMP:") }
      raise "no DUMP line in output:\n#{stdout}" unless line
      JSON.parse(line.sub(/\ADUMP:/, ""))
    end
  end

  def test_dev_access_url_adds_host_to_allowlist
    result = boot_and_dump(env: { "DEV_ACCESS_URL" => "http://salt-feature.prt.dev" })
    assert_includes result["hosts"], "salt-feature.prt.dev"
  end

  def test_dev_access_url_sets_application_default_url_options
    result = boot_and_dump(env: { "DEV_ACCESS_URL" => "http://salt-feature.prt.dev:3000" })
    assert_equal({ "host" => "salt-feature.prt.dev", "protocol" => "http", "port" => 3000 },
                 result["default_url_options"])
  end

  def test_dev_access_url_sets_action_mailer_default_url_options
    result = boot_and_dump(env: { "DEV_ACCESS_URL" => "https://salt-feature.prt.dev" })
    assert_equal "salt-feature.prt.dev", result["mailer_url_options"]["host"]
    assert_equal "https", result["mailer_url_options"]["protocol"]
  end

  def test_default_url_options_omits_default_port
    result = boot_and_dump(env: { "DEV_ACCESS_URL" => "https://salt-feature.prt.dev" })
    refute_includes result["default_url_options"].keys, "port"
  end

  def test_no_dev_access_url_does_not_set_default_url_options
    result = boot_and_dump
    assert_empty result["default_url_options"]
  end

  def test_no_dev_access_url_does_not_add_to_hosts
    result = boot_and_dump
    refute_includes result["hosts"], "salt-feature.prt.dev"
  end

  def test_ngrok_tunnel_adds_wildcard_to_hosts
    result = boot_and_dump(env: {
      "TUNNEL_PROVIDER" => "ngrok",
      "NGROK_URL" => "https://abc.gtltunnel.dev"
    })
    assert_includes result["hosts"], ".gtltunnel.dev"
  end

  def test_no_tunnel_does_not_add_wildcard
    result = boot_and_dump(env: { "TUNNEL_PROVIDER" => "none" })
    refute_includes result["hosts"], ".gtltunnel.dev"
    refute_includes result["hosts"], ".ngrok-free.app"
  end

  def test_session_cookie_domain_defaults_to_all_in_development
    result = boot_and_dump
    assert_equal "all", result["session_options"]["domain"]
  end

  def test_session_cookie_domain_opt_out
    result = boot_and_dump(app_config: "config.git_treeline_rails.cookie_domain = nil")
    refute_includes result["session_options"].keys, "domain"
  end

  def test_treeline_yml_loaded_env_drives_wiring
    result = boot_and_dump(
      treeline_yml: { "project" => "myapp" },
      env_local: <<~ENV
        DEV_ACCESS_URL="http://feature.prt.dev"
        TUNNEL_PROVIDER="ngrok"
        NGROK_URL="https://abc.gtltunnel.dev"
      ENV
    )
    assert_includes result["hosts"], "feature.prt.dev"
    assert_includes result["hosts"], ".gtltunnel.dev"
    assert_equal "feature.prt.dev", result["default_url_options"]["host"]
  end

  def test_app_can_override_default_url_options_via_later_initializer
    result = boot_and_dump(
      env: { "DEV_ACCESS_URL" => "http://salt-feature.prt.dev" },
      extra_files: {
        "config/initializers/override_url.rb" =>
          'Rails.application.default_url_options = { host: "explicit.example.com" }' + "\n"
      },
      app_config: 'config.paths["config/initializers"] << File.join(Dir.pwd, "config/initializers")'
    )
    assert_equal "explicit.example.com", result["default_url_options"]["host"]
  end
end
