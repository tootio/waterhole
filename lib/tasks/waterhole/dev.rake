namespace :waterhole do
  namespace :dev do
    desc "Print a sign-in link for a seeded moderator, development only: rake 'waterhole:dev:impersonate[avery]'"
    task :impersonate, [ :username ] => :environment do |_, args|
      abort "Refusing outside development." unless Rails.env.local?

      moderator = Moderator.find_by(username: args[:username]) || Moderator.first
      abort "No moderators. Run bin/rails db:seed first." if moderator.nil?

      token = Rails.application.message_verifier(:dev_sign_in)
        .generate({ moderator_id: moderator.id }, expires_in: 1.hour)
      puts "Open: #{Waterhole::Deployment.base_url}/dev/sign_in?token=#{token}"
      puts "Signs in as #{moderator.handle} for one hour. Development only."
    end
  end
end
