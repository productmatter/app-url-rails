# frozen_string_literal: true

require "uri"

module Git
  module Treeline
    module Rails
      class Railtie < ::Rails::Railtie
        TREELINE_CONFIG = ".treeline.yml"
        DEFAULT_ENV_TARGET = ".env.local"

        initializer "git_treeline.apply_allocation", before: :load_environment_config do
          next unless ::Rails.env.development?

          config_path = ::File.join(Dir.pwd, TREELINE_CONFIG)
          next unless ::File.exist?(config_path)

          env_target = Git::Treeline::Rails::Railtie.read_env_target(config_path)
          env_path = ::File.join(Dir.pwd, env_target)
          next unless ::File.exist?(env_path)

          Git::Treeline::Rails::Railtie.parse_env_file(env_path).each do |key, value|
            ENV[key] ||= value
          end
        end

        initializer "git_treeline.host_allowlist", before: :load_config_initializers do |app|
          next unless ::Rails.env.development?

          dev_host = Git::Treeline::Rails::Railtie.dev_access_host
          app.config.hosts << dev_host if dev_host

          wildcard = Git::Treeline::Rails::Railtie.tunnel_wildcard
          app.config.hosts << wildcard if wildcard
        end

        initializer "git_treeline.default_url_options", before: :load_config_initializers do
          next unless ::Rails.env.development?

          opts = Git::Treeline::Rails::Railtie.dev_access_url_options
          next if opts.nil?

          ::Rails.application.default_url_options = opts
          ::ActiveSupport.on_load(:action_mailer) do
            self.default_url_options = opts
          end
        end

        class << self
          def read_env_target(config_path)
            data = YAML.safe_load_file(config_path, permitted_classes: [Symbol]) || {}
            env_file = data["env_file"]
            return DEFAULT_ENV_TARGET unless env_file.is_a?(Hash)

            env_file["target"] || DEFAULT_ENV_TARGET
          rescue Psych::SyntaxError
            DEFAULT_ENV_TARGET
          end

          def parse_env_file(path)
            vars = {}
            ::File.foreach(path) do |line|
              line = line.strip
              next if line.empty? || line.start_with?("#")

              key, _, value = line.partition("=")
              next if key.empty? || value.nil?

              value = value.strip
              value = value[1..-2] if (value.start_with?('"') && value.end_with?('"')) ||
                                      (value.start_with?("'") && value.end_with?("'"))
              vars[key.strip] = value
            end
            vars
          end

          def dev_access_host
            url = ENV["DEV_ACCESS_URL"]
            return nil if url.nil? || url.empty?

            URI(url).host
          rescue URI::InvalidURIError
            nil
          end

          def dev_access_url_options
            url = ENV["DEV_ACCESS_URL"]
            return nil if url.nil? || url.empty?

            parsed = URI(url)
            opts = { host: parsed.host, protocol: parsed.scheme }
            opts[:port] = parsed.port unless parsed.port == parsed.default_port
            opts
          rescue URI::InvalidURIError
            nil
          end

          def tunnel_wildcard
            host = Git::Treeline::Rails::TunnelUrl.host
            return nil unless host

            parent = host.split(".", 2).last
            return nil unless parent&.include?(".")

            ".#{parent}"
          rescue Git::Treeline::Rails::GtlAdapter::Error => e
            ::Kernel.warn("[git-treeline-rails] tunnel discovery failed: #{e.message}")
            nil
          end
        end
      end
    end
  end
end
