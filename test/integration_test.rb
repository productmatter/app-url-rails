# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "yaml"
require "fileutils"
require "open3"

class RailtieIntegrationTest < Minitest::Test
  BOOT_SCRIPT = <<~'RUBY'
    require "rails"
    require "git/treeline/rails"

    ENV["RAILS_ENV"] = "development"

    module TreelineTestApp
      class Application < Rails::Application
        config.eager_load = false
        config.logger = Logger.new(File::NULL)
      end
    end

    Rails.application.initialize!

    missing = []
    %w[PORT DATABASE_NAME REDIS_URL].each do |key|
      expected = ENV.fetch("EXPECTED_#{key}", nil)
      actual = ENV.fetch(key, nil)
      if actual != expected
        missing << "#{key}: expected #{expected.inspect}, got #{actual.inspect}"
      end
    end

    if missing.any?
      abort "FAIL\n#{missing.join("\n")}"
    else
      puts "OK"
    end
  RUBY

  def test_railtie_sets_env_from_treeline_env_file
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".treeline.yml"), YAML.dump(
        "project" => "myapp",
        "env_file" => { "target" => ".env.local" }
      ))
      File.write(File.join(dir, ".env.local"), <<~ENV)
        PORT="3001"
        DATABASE_NAME="myapp_feature"
        REDIS_URL="redis://localhost:6379/2"
      ENV

      env = {
        "EXPECTED_PORT" => "3001",
        "EXPECTED_DATABASE_NAME" => "myapp_feature",
        "EXPECTED_REDIS_URL" => "redis://localhost:6379/2",
        "BUNDLE_GEMFILE" => File.join(__dir__, "..", "Gemfile")
      }

      stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "ruby", "-e", BOOT_SCRIPT, chdir: dir)

      assert status.success?, "Railtie boot failed:\nstdout: #{stdout}\nstderr: #{stderr}"
      assert_includes stdout, "OK"
    end
  end

  def test_railtie_does_not_overwrite_existing_env
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".treeline.yml"), YAML.dump(
        "project" => "myapp",
        "env_file" => { "target" => ".env.local" }
      ))
      File.write(File.join(dir, ".env.local"), <<~ENV)
        PORT="3001"
      ENV

      env = {
        "PORT" => "9999",
        "EXPECTED_PORT" => "9999",
        "EXPECTED_DATABASE_NAME" => nil,
        "EXPECTED_REDIS_URL" => nil,
        "BUNDLE_GEMFILE" => File.join(__dir__, "..", "Gemfile")
      }

      stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "ruby", "-e", BOOT_SCRIPT, chdir: dir)

      assert status.success?, "Railtie boot failed:\nstdout: #{stdout}\nstderr: #{stderr}"
      assert_includes stdout, "OK"
    end
  end

  def test_railtie_skips_when_no_treeline_yml
    Dir.mktmpdir do |dir|
      env = {
        "EXPECTED_PORT" => nil,
        "EXPECTED_DATABASE_NAME" => nil,
        "EXPECTED_REDIS_URL" => nil,
        "BUNDLE_GEMFILE" => File.join(__dir__, "..", "Gemfile")
      }

      stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "ruby", "-e", BOOT_SCRIPT, chdir: dir)

      assert status.success?, "Railtie boot failed:\nstdout: #{stdout}\nstderr: #{stderr}"
      assert_includes stdout, "OK"
    end
  end
end
