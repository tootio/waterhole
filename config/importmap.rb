# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "dompurify", to: "dompurify.min.js" # @3.4.15
pin "domfortify", to: "domfortify.min.js" # @1.0.2
pin "domfortify_init"
pin_all_from "app/javascript/controllers", under: "controllers"
