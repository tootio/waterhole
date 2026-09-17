class ApplicationMailer < ActionMailer::Base
  default from: -> { Waterhole::Deployment.mail_from }
  layout "mailer"
end
