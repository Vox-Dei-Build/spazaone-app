#!/usr/bin/env ruby
# frozen_string_literal: true

# Materializes the ignored Flutter .env from the registered production
# Firebase app configs. It validates identity before writing and never prints
# credentials or configuration values.

require 'json'
require 'open3'
require 'pathname'

root = Pathname.new(__dir__).parent
android_path = root.join('android/app/google-services.json')
ios_path = root.join('ios/GoogleService-Info.plist')
abort('Missing SpazaOne production Android Firebase config.') unless android_path.file?
abort('Missing SpazaOne production iOS Firebase config.') unless ios_path.file?

android = JSON.parse(android_path.read)
ios_json, ios_error, ios_status = Open3.capture3(
  '/usr/bin/plutil', '-convert', 'json', '-o', '-', ios_path.to_s
)
abort("Invalid production iOS Firebase config: #{ios_error}") unless ios_status.success?
ios = JSON.parse(ios_json)
project = android.fetch('project_info')
client = android.fetch('client').find do |candidate|
  candidate.dig('client_info', 'android_client_info', 'package_name') ==
    'com.tsepo.pasella'
end
abort('Production Android package is not registered.') unless client

unless project.fetch('project_id') == 'pasella-ledger' &&
       ios.fetch('PROJECT_ID') == 'pasella-ledger' &&
       ios.fetch('BUNDLE_ID') == 'com.tsepo.pasella'
  abort('Refusing to materialize .env from a non-production Firebase app.')
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
  '# Generated locally for SpazaOne production. Never commit this file.',
  *values.map { |key, value| "#{key}=#{value}" },
  ''
].join("\n")
root.join('.env').write(contents)
puts 'Materialized the ignored SpazaOne production Flutter environment.'
