// Only here for push: nothing is cached, and nothing is stored in the browser.
//
// Messages are Declarative Web Push (PushNotifications::Message), which a browser
// that supports it displays by itself without waking this worker. For the others,
// this shows the same JSON.
self.addEventListener("push", event => {
  const notification = event.data?.json().notification
  if (!notification) return

  event.waitUntil(self.registration.showNotification(notification.title, {
    body: notification.body,
    tag: notification.tag,
    renotify: notification.renotify,
    icon: "/icon.png",
    data: { navigate: notification.navigate }
  }))
})

self.addEventListener("notificationclick", event => {
  event.notification.close()

  const url = new URL(event.notification.data?.navigate || "/", self.location.origin)
  if (url.origin !== self.location.origin) return

  event.waitUntil(self.clients.openWindow(url.href))
})
