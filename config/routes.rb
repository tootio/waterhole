Rails.application.routes.draw do
  root "registration_requests#index"

  # --- authentication (Mastodon OAuth) ---------------------------------------
  resource :session, only: %i[new create destroy] do
    resource :recent_instance, only: :destroy
  end
  get "/oauth/callback", to: "sessions#callback", as: :oauth_callback
  # Public: fetched by an instance's Mastodon server, signed, while one of its
  # moderators signs in (see Instances::ProveIdentity).
  get "/identity_challenges/:token", to: "identity_challenges#show", as: :identity_challenge
  # Asked after signing in; decline signs out and deletes the moderator's data.
  resource :consent, only: %i[show create destroy]
  # The signed-in moderator's own avatar, served from here rather than their
  # media host; see AvatarsController.
  resource :avatar, only: :show

  # Public: an instance admin must be able to read the DNS instructions before
  # anyone on their server can sign in.
  resource :verification, only: %i[show create], path: "about"

  # --- the queue -------------------------------------------------------------
  resources :registration_requests, path: "requests", only: %i[index show] do
    member do
      get :next
      get :previous
    end
    resource  :claim,    only: %i[create destroy]
    resource  :decision, only: :create
    # Clears the applicant's personal data here; sync never imports it again.
    resource  :purge,    only: :create
    resources :notes,    only: :create
    # The current moderator's own vote: cast or change (update), withdraw (destroy).
    resource  :vote,     only: %i[update destroy]
  end
  resources :notes, only: %i[edit update destroy] # shallow: these need only the note id

  # --- instance administration ----------------------------------------------
  resource  :sync,      only: :create
  resources :sync_runs, only: :index
  resources :keyword_rules, except: :show
  resources :email_templates, except: :show

  resources :herds, only: %i[index show], controller: "instances", constraints: { id: /[^\/]+/ }

  # Development only; the controller refuses to act in any other environment.
  get "/dev/sign_in", to: "dev_sessions#create" if Rails.env.local?

  # Public: an instance admin must read these before accepting them in DNS, and a
  # moderator whose instance has fallen behind must still be able to reach them.
  get "/terms",   to: "legal#show", slug: "terms_of_service", as: :terms
  get "/privacy", to: "legal#show", slug: "privacy_policy",   as: :privacy
  get "/imprint", to: "legal#show", slug: "imprint",          as: :imprint

  # --- moderator help section -------------------------------------------------
  get "/help/shortcuts", to: "help#shortcuts", as: :keyboard_shortcuts_help
  get "/help/flags/:id", to: "help#flag",       as: :flag_help
  get "/help/regexp",    to: "help#regexp",     as: :regexp_help
  # Public: read by moderators whose sign-in just failed.
  get "/help/sign_in",   to: "help#sign_in",    as: :sign_in_help

  # Reveal health status on /up
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
