# When an instance lost access by being revoked or blocked; cleared if it is
# verified again. ForgetDepartedInstancesJob deletes its applications and
# moderators once it has been gone long enough.
class AddAccessEndedAtToInstances < ActiveRecord::Migration[8.1]
  def change
    add_column :instances, :access_ended_at, :datetime
  end
end
