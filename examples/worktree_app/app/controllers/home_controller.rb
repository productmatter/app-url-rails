class HomeController < ApplicationController
  def index
    @diagnostics = diagnostic_values
  end

  def diagnostics
    render json: diagnostic_values
  end

  def callback
    render json: { message: "The callback route is reachable.", **diagnostic_values }
  end

  private

  def diagnostic_values
    routes = Rails.application.routes.url_helpers
    {
      dev_url: ENV["DEV_URL"],
      tunnel_url: ENV["TUNNEL_URL"],
      base_url: AppUrl.base_url,
      public_base_url: AppUrl.public_base_url,
      callback_url: routes.callback_url,
      public_callback_url: routes.callback_url(**AppUrl.public_url_options),
      rails_version: Rails.version,
      app_url_version: AppUrl::VERSION,
      app_url_source: Gem.loaded_specs.fetch("app-url-rails").full_gem_path
    }
  end
end
