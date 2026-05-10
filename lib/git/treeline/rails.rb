# frozen_string_literal: true

require "yaml"
require_relative "rails/version"
require_relative "rails/gtl_adapter"
require_relative "rails/tunnel_url"
require_relative "rails/railtie"

::TunnelUrl = Git::Treeline::Rails::TunnelUrl unless defined?(::TunnelUrl)
