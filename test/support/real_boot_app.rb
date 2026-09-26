# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"

module RealBootApp
  APPLICATION_RB = <<~'RUBY'
    require "rails"
    require "action_controller/railtie"
    require "action_cable/engine" if ENV["WITH_ACTION_CABLE"] == "true"
    require "app-url-rails"

    module RealBootFixture
      class Application < Rails::Application
        config.eager_load = false
        config.logger = Logger.new(IO::NULL)
        config.root = File.expand_path("..", __dir__)
        config.secret_key_base = "real-boot-characterization-secret-key-base"
        config.hosts << "preserved.example"

        if config.respond_to?(:action_cable)
          config.action_cable.allowed_request_origins = ["https://preserved-origin.example"]
        end
      end
    end

    Rails.application.default_url_options = {
      host: "preserved.example",
      protocol: "https",
      port: 4444
    }
  RUBY

  DEVELOPMENT_RB = <<~RUBY
    Rails.application.configure do
      config.consider_all_requests_local = false
    end
  RUBY

  ENVIRONMENT_RB = <<~RUBY
    require_relative "application"

    Rails.application.initialize!
  RUBY

  ROUTES_RB = <<~RUBY
    Rails.application.routes.draw do
      get "/probe", to: ->(_env) { [200, { "content-type" => "text/plain" }, ["ok"]] }, as: :probe
    end
  RUBY

  module_function

  def build(root)
    write(root, "config/application.rb", APPLICATION_RB)
    write(root, "config/environment.rb", ENVIRONMENT_RB)
    write(root, "config/environments/development.rb", DEVELOPMENT_RB)
    write(root, "config/routes.rb", ROUTES_RB)

    require_relative "../../lib/generators/app_url/install_generator"
    Dir.chdir(root) do
      AppUrl::Generators::InstallGenerator.start([], destination_root: root)
    end
  end

  def boot(root, dev_url:, tunnel_url:, with_action_cable:)
    environment = {
      "DEV_URL" => dev_url,
      "RAILS_ENV" => "development",
      "RACK_ENV" => "development",
      "TUNNEL_URL" => tunnel_url,
      "WITH_ACTION_CABLE" => with_action_cable.to_s
    }
    command = [RbConfig.ruby, "-rbundler/setup", __FILE__, "probe", root]
    stdout, stderr, status = Open3.capture3(environment, *command)

    raise "Real boot failed:\n#{stderr}\n#{stdout}" unless status.success?

    JSON.parse(stdout)
  end

  def probe(root)
    require File.join(root, "config/environment")
    require "rack/mock"

    result = {
      "url_options" => AppUrl.url_options.transform_keys(&:to_s),
      "base_url" => AppUrl.base_url,
      "route_url" => Rails.application.routes.url_helpers.probe_url,
      "public_url" => AppUrl.public_url,
      "public_host" => AppUrl.public_host,
      "public_url_options" => AppUrl.public_url_options.transform_keys(&:to_s),
      "public_base_url" => AppUrl.public_base_url,
      "host_statuses" => host_statuses
    }
    result["cable_origins"] = cable_origins if defined?(ActionCable::Connection::Base)
    puts JSON.generate(result)
  end

  def host_statuses
    %w[preserved.example dev.example tunnel.example unrelated.example].to_h do |host|
      response = Rack::MockRequest.new(Rails.application).get("/probe", "HTTP_HOST" => host)
      [host, response.status]
    end
  end

  def cable_origins
    origins = {
      "preserved" => "https://preserved-origin.example",
      "dev" => "http://dev.example:99999",
      "dev_wrong_scheme" => "https://dev.example:3100",
      "dev_lookalike" => "http://dev.example.evil:3100",
      "tunnel" => "https://tunnel.example:99999",
      "tunnel_wrong_scheme" => "http://tunnel.example:4443",
      "tunnel_lookalike" => "https://tunnel.example.evil:4443",
      "unrelated" => "https://unrelated.example"
    }

    origins.transform_values { |origin| cable_origin_allowed?(origin) }
  end

  def cable_origin_allowed?(origin)
    env = Rack::MockRequest.env_for(
      "http://socket.example/cable",
      "HTTP_HOST" => "socket.example",
      "HTTP_ORIGIN" => origin
    )
    connection = ActionCable::Connection::Base.allocate
    connection.instance_variable_set(:@server, ActionCable.server)
    connection.instance_variable_set(:@env, env)
    connection.instance_variable_set(:@logger, Rails.logger)
    connection.send(:allow_request_origin?)
  end

  def write(root, relative_path, contents)
    path = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
  end
end

RealBootApp.probe(ARGV.fetch(1)) if $PROGRAM_NAME == __FILE__ && ARGV.first == "probe"
