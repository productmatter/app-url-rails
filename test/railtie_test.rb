# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "tempfile"
require "fileutils"

require_relative "../lib/git/treeline/rails/version"

# Load the Railtie class without requiring Rails by stubbing the constant.
require "active_support/ordered_options"

module Rails
  class Railtie
    def self.initializer(*); end
    def self.config
      @config ||= ActiveSupport::OrderedOptions.new
    end
  end
end

require_relative "../lib/git/treeline/rails/gtl_adapter"
require_relative "../lib/git/treeline/rails/tunnel_url"
require_relative "../lib/git/treeline/rails/railtie"

class ReadEnvTargetTest < Minitest::Test
  def write_yaml(data)
    f = Tempfile.new([".treeline", ".yml"])
    f.write(YAML.dump(data))
    f.close
    f
  end

  def test_reads_custom_target
    f = write_yaml("project" => "myapp", "env_file" => { "target" => ".env.development" })
    assert_equal ".env.development", Git::Treeline::Rails::Railtie.read_env_target(f.path)
  ensure
    f&.unlink
  end

  def test_defaults_when_env_file_missing
    f = write_yaml("project" => "myapp")
    assert_equal ".env.local", Git::Treeline::Rails::Railtie.read_env_target(f.path)
  ensure
    f&.unlink
  end

  def test_defaults_when_target_key_missing
    f = write_yaml("project" => "myapp", "env_file" => { "source" => ".env" })
    assert_equal ".env.local", Git::Treeline::Rails::Railtie.read_env_target(f.path)
  ensure
    f&.unlink
  end

  def test_defaults_on_malformed_yaml
    f = Tempfile.new([".treeline", ".yml"])
    f.write("{{{{not yaml")
    f.close
    assert_equal ".env.local", Git::Treeline::Rails::Railtie.read_env_target(f.path)
  ensure
    f&.unlink
  end
end

class ParseEnvFileTest < Minitest::Test
  def write_env(content)
    f = Tempfile.new(".env")
    f.write(content)
    f.close
    f
  end

  def test_parses_double_quoted_values
    f = write_env(<<~ENV)
      PORT="3001"
      DATABASE_NAME="myapp_feature"
    ENV
    vars = Git::Treeline::Rails::Railtie.parse_env_file(f.path)
    assert_equal "3001", vars["PORT"]
    assert_equal "myapp_feature", vars["DATABASE_NAME"]
  ensure
    f&.unlink
  end

  def test_parses_single_quoted_values
    f = write_env("REDIS_URL='redis://localhost:6379/2'\n")
    vars = Git::Treeline::Rails::Railtie.parse_env_file(f.path)
    assert_equal "redis://localhost:6379/2", vars["REDIS_URL"]
  ensure
    f&.unlink
  end

  def test_parses_unquoted_values
    f = write_env("PORT=3001\n")
    vars = Git::Treeline::Rails::Railtie.parse_env_file(f.path)
    assert_equal "3001", vars["PORT"]
  ensure
    f&.unlink
  end

  def test_skips_comments_and_blanks
    f = write_env(<<~ENV)
      # This is a comment
      PORT="3001"

      # Another comment
      DATABASE_NAME="myapp"
    ENV
    vars = Git::Treeline::Rails::Railtie.parse_env_file(f.path)
    assert_equal 2, vars.size
    assert_equal "3001", vars["PORT"]
    assert_equal "myapp", vars["DATABASE_NAME"]
  ensure
    f&.unlink
  end

  def test_handles_values_containing_equals
    f = write_env('DATABASE_URL="postgres://localhost/myapp?sslmode=disable"' + "\n")
    vars = Git::Treeline::Rails::Railtie.parse_env_file(f.path)
    assert_equal "postgres://localhost/myapp?sslmode=disable", vars["DATABASE_URL"]
  ensure
    f&.unlink
  end

  def test_handles_empty_file
    f = write_env("")
    vars = Git::Treeline::Rails::Railtie.parse_env_file(f.path)
    assert_equal({}, vars)
  ensure
    f&.unlink
  end

  def test_matches_go_cli_output_format
    f = write_env(<<~ENV)
      PORT="3001"
      DATABASE_NAME="myapp_feature"
      REDIS_URL="redis://localhost:6379/2"
    ENV
    vars = Git::Treeline::Rails::Railtie.parse_env_file(f.path)
    assert_equal({ "PORT" => "3001", "DATABASE_NAME" => "myapp_feature", "REDIS_URL" => "redis://localhost:6379/2" }, vars)
  ensure
    f&.unlink
  end
end
