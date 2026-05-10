# frozen_string_literal: true

require "open3"
require "json"

module Git
  module Treeline
    module Rails
      module GtlAdapter
        class Error < StandardError; end

        class << self
          def tunnel_url
            tunnel = routes["tunnel"]
            return tunnel if tunnel.is_a?(String) && !tunnel.empty?

            raise Error, no_tunnel_configured_message
          end

          private

          def routes
            stdout, stderr, status = Open3.capture3("gtl", "routes", "--json")
            raise Error, gtl_failed_message(stderr) unless status.success?

            JSON.parse(stdout)
          rescue Errno::ENOENT
            raise Error, gtl_not_installed_message
          rescue JSON::ParserError => e
            raise Error, "`gtl routes --json` returned invalid JSON: #{e.message}"
          end

          def gtl_failed_message(stderr)
            detail = stderr.to_s.strip
            detail = "unknown error" if detail.empty?
            "`gtl routes --json` failed: #{detail}. " \
              "Is this directory a configured git-treeline worktree?"
          end

          def gtl_not_installed_message
            "`gtl` command not found. Install git-treeline: " \
              "brew install git-treeline/tap/git-treeline"
          end

          def no_tunnel_configured_message
            "`gtl routes --json` returned no tunnel URL. " \
              "Run `gtl tunnel setup` to configure a Cloudflare tunnel, " \
              "or set TUNNEL_PROVIDER=none if this worktree doesn't need public access."
          end
        end
      end
    end
  end
end
