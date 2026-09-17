# What a batch of generated signups tends to have in common even when every one
# arrives through a different residential proxy: the email provider, the
# pattern of the username, and the browser's language.
#
# The username pattern keeps separators and turns each run of letters into "a"
# and each run of digits into "9": john.smith84 and anna.berg2 are both a.a9.
#
#   "gmail.com a.a9 en"
module SignupShape
  module_function

  def call(email_domain:, username:, locale:)
    return nil if email_domain.blank? || username.blank?

    [ email_domain, pattern(username), locale.presence || "-" ].join(" ")
  end

  def pattern(username) = username.downcase.gsub(/\p{L}+/, "a").gsub(/\p{N}+/, "9")
end
