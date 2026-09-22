module HelpHelper
  # Shared between the queue and the request detail page, the two places a
  # moderator is using the shortcuts this links to.
  def keyboard_shortcuts_link
    tag.p class: "mt-6 text-sm" do
      link_to keyboard_shortcuts_help_path,
        class: button_classes(:ghost, "rounded hover:text-stone-900 dark:hover:text-stone-100"),
        data: { action: "modal#open" } do
        tag.span("ⓘ ", aria_hidden: true) + "Keyboard shortcuts"
      end
    end
  end
end
