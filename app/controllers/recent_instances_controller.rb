# Lets someone on a shared computer drop an instance from the sign-in page's
# per-browser list. Touches only this browser's cookie.
class RecentInstancesController < ApplicationController
  allow_unauthenticated_access

  def destroy
    forget_recent_instance(params[:domain].to_s)
    redirect_to new_session_path
  end
end
