# Mail for whoever runs this Waterhole (WATERHOLE_OPERATOR_EMAIL).
class OperatorMailer < ApplicationMailer
  # An instance's DNS record now asks for cross-instance signals, and nothing
  # happens until the operator approves -- so without this, a request could
  # sit unnoticed for as long as nobody runs `rake waterhole:herd:signals`.
  def signals_requested(instance)
    @instance = instance
    @host = Waterhole::Deployment.host

    mail to: Waterhole::Deployment.operator_emails,
      subject: "[Waterhole] #{instance.domain} asks to join cross-instance signals"
  end
end
