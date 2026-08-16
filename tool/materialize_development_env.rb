#!/usr/bin/env ruby
# frozen_string_literal: true

# Materializes the ignored Flutter .env from the downloaded development
# Firebase app configs. It never prints credentials or configuration values.

require 'json'
require 'open3'
require 'pathname'

root = Pathname.new(__dir__).parent
android_path = root.join('android/app/src/development/google-services.json')
ios_path = root.join('ios/GoogleService-Info-development.plist')
abort('Missing SpazaOne Development Android Firebase config.') unless android_path.file?
abort('Missing SpazaOne Development iOS Firebase config.') unless ios_path.file?

android = JSON.parse(android_path.read)
ios_json, ios_error, ios_status = Open3.capture3(
  '/usr/bin/plutil', '-convert', 'json', '-o', '-', ios_path.to_s
)
abort("Invalid development iOS Firebase config: #{ios_error}") unless ios_status.success?
ios = JSON.parse(ios_json)
project = android.fetch('project_info')
client = android.fetch('client').find do |candidate|
  candidate.dig('client_info', 'android_client_info', 'package_name') ==
    'com.tsepo.spazaone.dev'
end
abort('Development Android package is not registered.') unless client

unless project.fetch('project_id') == 'spazaone-dev' &&
       ios.fetch('PROJECT_ID') == 'spazaone-dev' &&
       ios.fetch('BUNDLE_ID') == 'com.tsepo.spazaone.dev'
  abort('Refusing to materialize .env from a non-development Firebase app.')
end

android_api_key = client.fetch('api_key').first.fetch('current_key')
values = {
  'FIREBASE_ANDROID_API_KEY' => android_api_key,
  'FIREBASE_ANDROID_APP_ID' => client.dig('client_info', 'mobilesdk_app_id'),
  'FIREBASE_ANDROID_MESSAGING_SENDER_ID' => project.fetch('project_number'),
  'FIREBASE_ANDROID_PROJECT_ID' => project.fetch('project_id'),
  'FIREBASE_ANDROID_STORAGE_BUCKET' => project.fetch('storage_bucket'),
  'FIREBASE_IOS_API_KEY' => ios.fetch('API_KEY'),
  'FIREBASE_IOS_APP_ID' => ios.fetch('GOOGLE_APP_ID'),
  'FIREBASE_IOS_MESSAGING_SENDER_ID' => ios.fetch('GCM_SENDER_ID'),
  'FIREBASE_IOS_PROJECT_ID' => ios.fetch('PROJECT_ID'),
  'FIREBASE_IOS_STORAGE_BUCKET' => ios.fetch('STORAGE_BUCKET'),
  'FIREBASE_IOS_CLIENT_ID' => ios.fetch('CLIENT_ID', ''),
  'FIREBASE_IOS_BUNDLE_ID' => ios.fetch('BUNDLE_ID')
}

contents = [
  '# Generated locally for SpazaOne Development. Never commit this file.',
  *values.map { |key, value| "#{key}=#{value}" },
  ''
].join("\n")
root.join('.env').write(contents)
puts 'Materialized the ignored SpazaOne Development Flutter environment.'
