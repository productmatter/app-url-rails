# frozen_string_literal: true

require_relative "lib/tunnel_url/version"

Gem::Specification.new do |spec|
  spec.name = "tunnel-url-rails"
  spec.version = TunnelUrl::VERSION
  spec.authors = ["Jonathan Simmons"]
  spec.email = ["jonathan@productmatter.co"]

  spec.summary = "Tiny helper for generating outsider-reachable URLs in Rails apps with a development tunnel."
  spec.description = "Provider-agnostic TunnelUrl class. Reads TUNNEL_URL from the environment and " \
                     "exposes a small API (url, host, base_url, public_url_options, public_base_url) " \
                     "for building public URLs at request time — tunnel preferred, falling back to " \
                     "Rails.application.default_url_options."
  spec.homepage = "https://github.com/productmatter/tunnel-url-rails"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/releases"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "LICENSE.txt", "README.md"]
  spec.require_paths = ["lib"]
end
