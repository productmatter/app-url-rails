# frozen_string_literal: true

require_relative "lib/app_url/version"

Gem::Specification.new do |spec|
  spec.name = "app-url-rails"
  spec.version = AppUrl::VERSION
  spec.authors = ["Jonathan Simmons"]
  spec.email = ["jonathan@productmatter.co"]

  spec.summary = "One place to get your Rails app's URL — with an optional tunnel override for development."
  spec.description = "AppUrl gives every callsite in your Rails app a single, consistent way to ask " \
                     "for the app's URL — replacing scattered host/port string-building. Returns the " \
                     "app's configured URL by default; AppUrl.public_* methods return TUNNEL_URL when " \
                     "set (for webhook callbacks, SMS links, OAuth redirects) and fall back to the " \
                     "default otherwise. No Railtie; an install generator wires DEV_URL and TUNNEL_URL " \
                     "into config/environments/development.rb."
  spec.homepage = "https://github.com/productmatter/app-url-rails"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/releases"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "LICENSE.txt", "README.md"]
  spec.require_paths = ["lib"]
end
