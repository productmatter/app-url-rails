# frozen_string_literal: true

require "uri"

module Git
  module Treeline
    module Rails
      class TunnelUrl
        @providers = {}

        class << self
          attr_reader :providers

          def register(name, &block)
            raise ArgumentError, "register requires a block" unless block

            @providers[name.to_s] = block
          end

          def url
            return @url if defined?(@url)

            provider = ENV.fetch("TUNNEL_PROVIDER", "none")
            block = @providers[provider] or
              raise ArgumentError,
                "Unknown TUNNEL_PROVIDER=#{provider.inspect}. " \
                "Registered providers: #{@providers.keys.join(', ')}."

            @url = block.call
          end

          def host
            url && URI(url).host
          end

          def public_url_options
            parsed = URI(url || ENV.fetch("DEV_ACCESS_URL"))
            opts = { host: parsed.host, protocol: parsed.scheme }
            opts[:port] = parsed.port unless parsed.port == parsed.default_port
            opts
          end

          def public_base_url
            url || ENV.fetch("DEV_ACCESS_URL")
          end

          def reset!
            remove_instance_variable(:@url) if defined?(@url)
          end
        end
      end
    end
  end
end

Git::Treeline::Rails::TunnelUrl.register(:gtl)   { Git::Treeline::Rails::GtlAdapter.tunnel_url }
Git::Treeline::Rails::TunnelUrl.register(:ngrok) { ENV.fetch("NGROK_URL") }
Git::Treeline::Rails::TunnelUrl.register(:none)  { nil }
