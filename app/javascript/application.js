// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "domfortify_init"
import { Turbo, cable } from "@hotwired/turbo-rails"
import "controllers"

// Turbo's default disables the submit button for the length of the request,
// and disabling a focused button drops focus to <body> -- so after any form
// whose turbo stream replaces itself (the claim banner), Turbo's own focus
// restoration finds nothing to restore. aria-disabled blocks repeat clicks the
// same way while leaving focus where the moderator put it.
Turbo.config.forms.submitter = "aria-disabled"

// Proactively disconnect the WebSocket before entering the bfcache and reconnect
// when loaded from it again.
let consumer
cable.getConsumer().then((c) => { consumer = c })

addEventListener("pagehide", (event) => {
  if (!event.persisted || !consumer) return
  consumer.disconnect()
  // disconnect() only closes an open socket; one mid-reconnect would still
  // be caught connecting.
  const socket = consumer.connection.webSocket
  if (socket?.readyState === WebSocket.CONNECTING) socket.close()
})

addEventListener("pageshow", (event) => {
  if (event.persisted && consumer?.subscriptions.subscriptions.length) consumer.connect()
})
