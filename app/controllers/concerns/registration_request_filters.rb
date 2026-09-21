module RegistrationRequestFilters
  extend ActiveSupport::Concern

  private

  # Built from the permitted filters only. Handing url_for the raw query
  # string let ?host= and ?protocol= rewrite a link into another origin or a
  # javascript: URL.
  def filter_params = params.permit(*RegistrationRequestsHelper::FILTER_PARAMS).to_h

  def filtered_registration_requests
    RegistrationRequests::Query.new(registration_requests_scope, filter_params, viewer: current_moderator).call
  end
end
