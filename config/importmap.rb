# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "dompurify" # @3.4.16
pin "domfortify" # @1.0.3
pin "domfortify_init"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/lib", under: "lib"
# Not `bin/importmap pin`: its tom-select build imports ~15 relative files that
# pinning does not fetch. These are jsDelivr's single-file +esm bundles, with
# their imports of each other rewritten to the bare names below.
pin "tom-select" # @2.6.2
pin "@orchidjs/sifter", to: "@orchidjs--sifter.js" # @1.1.0
pin "@orchidjs/unicode-variants", to: "@orchidjs--unicode-variants.js" # @1.1.2
