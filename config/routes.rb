Rails.application.routes.draw do
  root "registration_requests#index"

  # --- authentication (Mastodon OAuth) ---------------------------------------
  resource :session, only: %i[new create destroy] do
    resource :recent_instance, only: :destroy
  end
  get "/oauth/callback", to: "sessions#callback", as: :oauth_callback
  # Asked after signing in; decline signs out and deletes the moderator's data.
  resource :consent, only: %i[show create destroy]

  # Public: an instance admin must be able to read the DNS instructions before
  # anyone on their server can sign in.
  resource :verification, only: %i[show create], path: "about"

  # --- the queue -------------------------------------------------------------
  resources :registration_requests, path: "requests", only: %i[index show] do
    resource  :claim,    only: %i[create destroy]
    resource  :decision, only: :create
    # Clears the applicant's personal data here; sync never imports it again.
    resource  :purge,    only: :create
    resources :notes,    only: :create
  end
  resources :notes, only: %i[edit update destroy] # shallow: these need only the note id

  # --- instance administration ----------------------------------------------
  resource  :sync,      only: :create
  resources :sync_runs, only: :index
  resources :keyword_rules, except: :show
  # "Herds" in the interface: the app's own word for the servers that come down
  # to this waterhole (see shared/_about). The model stays Instance, which is
  # what Mastodon calls them.
  #
  # Addressed by domain, including your own -- there is nothing special about
  # being the viewer. Instance#to_param supplies it.
  #
  # The segment stays :id rather than the truer :domain, because url_for treats
  # :domain as part of the HOST -- subdomain, domain, tld -- so a :domain
  # segment is dropped on the floor and every path helper raises "missing
  # required keys". The constraint is what lets a dotted domain through: the
  # format segment would otherwise take the TLD for an .html.
  resources :herds, only: %i[index show], controller: "instances",
    constraints: { id: /[^\/]+/ }

  # Development only; the controller refuses to act in any other environment.
  get "/dev/sign_in", to: "dev_sessions#create" if Rails.env.local?

  # Public: an instance admin must read these before accepting them in DNS, and a
  # moderator whose instance has fallen behind must still be able to reach them.
  get "/terms",   to: "legal#show", slug: "terms_of_service", as: :terms
  get "/privacy", to: "legal#show", slug: "privacy_policy",   as: :privacy
  get "/imprint", to: "legal#show", slug: "imprint",          as: :imprint

  # Reveal health status on /up
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
