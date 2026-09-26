Rails.application.routes.draw do
  root "home#index"
  get "/diagnostics", to: "home#diagnostics"
  get "/callback", to: "home#callback", as: :callback
  mount ActionCable.server => "/cable"
end
