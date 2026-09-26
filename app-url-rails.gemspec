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
                     "app's configured URL by default; public URL helpers expose TUNNEL_URL for " \
                     "webhook callbacks, SMS links, and OAuth redirects. No Railtie; an install " \
                     "generator adds an explicit development " \
                     "setup call, with URL validation and wiring maintained in the gem."
  spec.homepage = "https://github.com/productmatter/app-url-rails"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/releases"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "LICENSE.txt", "README.md"]
  spec.require_paths = ["lib"]
end
