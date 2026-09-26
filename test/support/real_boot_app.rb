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
        config.force_ssl = ENV["FORCE_SSL"] == "true"
        config.logger = Logger.new(IO::NULL)
        config.root = File.expand_path("..", __dir__)
        config.secret_key_base = "real-boot-characterization-secret-key-base"
        config.hosts << "preserved.example"

        if config.respond_to?(:action_cable)
          config.action_cable.allowed_request_origins = ["https://preserved-origin.example"]
        end
      end
    end

    default_url_options = {
      host: "preserved.example",
      port: 4444
    }
    default_url_options[:protocol] = "https" unless ENV["OMIT_PROTOCOL"] == "true"
    default_url_options[:locale] = "en" if ENV["EXTRA_DEFAULT"] == "true"
    Rails.application.default_url_options = default_url_options
  RUBY

  DEVELOPMENT_RB = <<~RUBY
    Rails.application.configure do
      config.consider_all_requests_local = false
    end
  RUBY

  LEGACY_WIRING = <<~'RUBY'.lines.map { |line| line.strip.empty? ? line : "  #{line}" }.join
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

  ENVIRONMENT_RB = <<~RUBY
    require_relative "application"

    Rails.application.initialize!
  RUBY

  ROUTES_RB = <<~RUBY
    Rails.application.routes.draw do
      get "/probe", to: ->(_env) { [200, { "content-type" => "text/plain" }, ["ok"]] }, as: :probe
    end
  RUBY

  TEST_RB = <<~RUBY
    Rails.application.configure do
      AppUrl.configure_development!(config)
    end
  RUBY

  module_function

  def build(root, installation: :generator, repeat_setup: false, capture_setup_error: false)
    write(root, "config/application.rb", APPLICATION_RB)
    write(root, "config/environment.rb", ENVIRONMENT_RB)
    development_rb = if installation == :manual
                       DEVELOPMENT_RB.sub("  config.consider", "#{LEGACY_WIRING}  config.consider")
                     else
                       DEVELOPMENT_RB
                     end
    write(root, "config/environments/development.rb", development_rb)
    write(root, "config/environments/test.rb", installation == :none ? DEVELOPMENT_RB : TEST_RB)
    write(root, "config/routes.rb", ROUTES_RB)

    if installation == :generator
      load_generator
      Dir.chdir(root) do
        AppUrl::Generators::InstallGenerator.start([], destination_root: root)
      end
    elsif installation == :manual
      migrate_legacy_setup(root)
    end

    repeat_setup_call(root) if repeat_setup
    capture_setup_error(root) if capture_setup_error
  end

  def boot(root, dev_url:, tunnel_url:, with_action_cable:, rails_env: "development",
           force_ssl: false, omit_protocol: false, extra_default: false, public_helper: nil)
    environment = {
      "DEV_URL" => dev_url,
      "EXTRA_DEFAULT" => extra_default.to_s,
      "FORCE_SSL" => force_ssl.to_s,
      "OMIT_PROTOCOL" => omit_protocol.to_s,
      "PUBLIC_HELPER" => public_helper&.to_s,
      "RAILS_ENV" => rails_env,
      "RACK_ENV" => rails_env,
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

    if ENV["PUBLIC_HELPER"]
      puts JSON.generate(public_helper_result(ENV.fetch("PUBLIC_HELPER")))
      return
    end

    if $app_url_setup_error
      puts JSON.generate(setup_error_result)
      return
    end

    result = {
      "url_options" => AppUrl.url_options.transform_keys(&:to_s),
      "base_url" => AppUrl.base_url,
      "route_url" => Rails.application.routes.url_helpers.probe_url,
      "public_url" => AppUrl.public_url,
      "public_host" => AppUrl.public_host,
      "public_url_options" => AppUrl.public_url_options.transform_keys(&:to_s),
      "public_base_url" => AppUrl.public_base_url,
      "public_route_url" => Rails.application.routes.url_helpers.probe_url(**AppUrl.public_url_options),
      "host_counts" => configured_host_counts,
      "host_statuses" => host_statuses
    }
    if defined?(ActionCable::Connection::Base)
      result["cable_origin_count"] = Rails.application.config.action_cable.allowed_request_origins.size
      result["cable_origins"] = cable_origins
    end
    puts JSON.generate(result)
  end

  def host_statuses
    %w[preserved.example dev.example tunnel.example unrelated.example].to_h do |host|
      response = Rack::MockRequest.new(Rails.application).get("/probe", "HTTP_HOST" => host)
      [host, response.status]
    end
  end

  def configured_host_counts
    %w[preserved.example dev.example tunnel.example].to_h do |host|
      [host, Rails.application.config.hosts.count(host)]
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

  def load_generator
    require_relative "../../lib/generators/app_url/install_generator"
  end

  def install_setup_call(root)
    load_generator
    path = File.join(root, "config/environments/development.rb")
    source = File.read(path)
    installation = "  #{AppUrl::Generators::InstallGenerator::FORMAT_MARKER}\n" \
                   "  #{AppUrl::Generators::InstallGenerator::SETUP_CALL}\n"
    File.write(path, source.sub("Rails.application.configure do\n", "Rails.application.configure do\n#{installation}"))
  end

  def migrate_legacy_setup(root)
    path = File.join(root, "config/environments/development.rb")
    source = File.read(path)
    File.write(path, source.sub(LEGACY_WIRING, ""))
    install_setup_call(root)
  end

  def repeat_setup_call(root)
    path = File.join(root, "config/environments/development.rb")
    source = File.read(path)
    call = "  AppUrl.configure_development!(config)\n"
    File.write(path, source.sub(call, call * 2))
  end

  def capture_setup_error(root)
    path = File.join(root, "config/environments/development.rb")
    source = File.read(path)
    call = "  AppUrl.configure_development!(config)\n"
    replacement = <<~RUBY.lines.map { |line| line.empty? ? line : "  #{line}" }.join
      begin
        AppUrl.configure_development!(config)
      rescue AppUrl::ConfigurationError => error
        $app_url_setup_error = error
      end
    RUBY
    File.write(path, source.sub(call, replacement))
  end

  def setup_error_result
    {
      "setup_error" => {
        "class" => $app_url_setup_error.class.name,
        "message" => $app_url_setup_error.message,
        "cause" => $app_url_setup_error.cause&.message
      },
      "url_options" => AppUrl.url_options.transform_keys(&:to_s),
      "host_counts" => configured_host_counts,
      "host_statuses" => host_statuses,
      "cable_origin_count" => if defined?(ActionCable::Connection::Base)
                                Rails.application.config.action_cable.allowed_request_origins.size
                              end
    }
  end

  def public_helper_result(helper)
    { "value" => AppUrl.public_send(helper) }
  rescue AppUrl::ConfigurationError => error
    {
      "error" => {
        "class" => error.class.name,
        "message" => error.message,
        "cause" => error.cause&.message
      }
    }
  end
end

RealBootApp.probe(ARGV.fetch(1)) if $PROGRAM_NAME == __FILE__ && ARGV.first == "probe"
