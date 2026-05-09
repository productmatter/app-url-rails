# frozen_string_literal: true

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
        end
      end
    end
  end
end
