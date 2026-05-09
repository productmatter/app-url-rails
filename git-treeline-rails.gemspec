# frozen_string_literal: true

require_relative "lib/git/treeline/rails/version"

Gem::Specification.new do |spec|
  spec.name = "git-treeline-rails"
  spec.version = Git::Treeline::Rails::VERSION
  spec.authors = ["Jonathan Simmons"]
  spec.email = ["jonathan@productmatter.co"]

  spec.summary = "Rails integration for git-treeline — auto-loads worktree ENV vars at boot."
  spec.description = "Railtie that reads the env file written by the git-treeline CLI and sets " \
                     "allocated values (PORT, DATABASE_NAME, REDIS_URL, etc.) in ENV before " \
                     "Rails initializers run. Requires the git-treeline CLI (brew install " \
                     "git-treeline/tap/git-treeline)."
  spec.homepage = "https://github.com/git-treeline/git-treeline-rails"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["source_code_uri"] = "https://github.com/git-treeline/git-treeline-rails"
  spec.metadata["changelog_uri"] = "https://github.com/git-treeline/git-treeline-rails/releases"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "LICENSE.txt", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 7.0", "< 9"
end
