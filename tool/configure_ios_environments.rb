#!/usr/bin/env ruby
# frozen_string_literal: true

# Idempotently creates the iOS development/production configurations used by
# Flutter flavors. Keep this script checked in so a clean checkout can verify
# and repair the Xcode project without relying on manual Xcode changes.

require 'fileutils'
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'ios', 'Runner.xcodeproj')
SCHEME_DIR = File.join(PROJECT_PATH, 'xcshareddata', 'xcschemes')

ENVIRONMENTS = {
  'development' => {
    app_id: 'com.tsepo.spazaone.dev',
    display_name: 'SpazaOne Dev',
    dart_define: 'U1BBWkFPTkVfRU5WSVJPTk1FTlQ9ZGV2ZWxvcG1lbnQ='
  },
  'production' => {
    app_id: 'com.tsepo.pasella',
    display_name: 'SpazaOne',
    dart_define: 'U1BBWkFPTkVfRU5WSVJPTk1FTlQ9cHJvZHVjdGlvbg=='
  }
}.freeze

BASE_CONFIGURATIONS = %w[Debug Profile Release].freeze

def ensure_configuration(owner, name, source_name)
  existing = owner.build_configurations.find { |config| config.name == name }
  source = owner.build_configurations.find { |config| config.name == source_name }
  raise "Missing source configuration #{source_name}" unless source

  unless existing
    project = owner.is_a?(Xcodeproj::Project) ? owner : owner.project
    existing = project.new(
      Xcodeproj::Project::Object::XCBuildConfiguration
    )
    existing.name = name
    owner.build_configuration_list.build_configurations << existing
  end
  existing.build_settings = source.build_settings.dup
  existing.base_configuration_reference = source.base_configuration_reference
  existing
end

project = Xcodeproj::Project.open(PROJECT_PATH)

ENVIRONMENTS.each_key do |environment|
  BASE_CONFIGURATIONS.each do |base|
    ensure_configuration(project, "#{base}-#{environment}", base)
    project.targets.each do |target|
      ensure_configuration(target, "#{base}-#{environment}", base)
    end
  end
end

runner = project.targets.find { |target| target.name == 'Runner' }
tests = project.targets.find { |target| target.name == 'RunnerTests' }
raise 'Runner target missing' unless runner

ENVIRONMENTS.each do |environment, values|
  BASE_CONFIGURATIONS.each do |base|
    config = runner.build_configurations.find do |candidate|
      candidate.name == "#{base}-#{environment}"
    end
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = values[:app_id]
    config.build_settings['SPAZAONE_ENVIRONMENT'] = environment
    config.build_settings['SPAZAONE_DISPLAY_NAME'] = values[:display_name]
    config.build_settings['DART_DEFINES'] = "$(inherited),#{values[:dart_define]}"

    next unless tests

    test_config = tests.build_configurations.find do |candidate|
      candidate.name == "#{base}-#{environment}"
    end
    test_config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] =
      "#{values[:app_id]}.RunnerTests"
  end
end

# GoogleService-Info.plist must be selected explicitly by environment. Keeping
# the production plist in Copy Bundle Resources would let a development build
# silently initialize production before Dart gets a chance to reject it.
project.targets.each do |target|
  next unless target.respond_to?(:resources_build_phase)

  target.resources_build_phase.files.to_a.each do |build_file|
    reference = build_file.file_ref
    next unless reference&.path == 'GoogleService-Info.plist'

    target.resources_build_phase.remove_build_file(build_file)
  end
end

phase = runner.shell_script_build_phases.find do |candidate|
  candidate.name == 'Select SpazaOne Firebase configuration'
end
phase ||= runner.new_shell_script_build_phase(
  'Select SpazaOne Firebase configuration'
)
phase.shell_path = '/bin/sh'
phase.show_env_vars_in_log = '0'
phase.input_paths = [
  '$(PROJECT_DIR)/GoogleService-Info.plist',
  '$(PROJECT_DIR)/GoogleService-Info-development.plist'
]
phase.output_paths = [
  '$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/GoogleService-Info.plist'
]
phase.shell_script = <<~'SH'
  set -eu

  case "${SPAZAONE_ENVIRONMENT}" in
    development)
      SOURCE_PLIST="${PROJECT_DIR}/GoogleService-Info-development.plist"
      EXPECTED_PROJECT="spazaone-dev"
      FALLBACK_PROJECT="spazaone-dev-za"
      ;;
    production)
      SOURCE_PLIST="${PROJECT_DIR}/GoogleService-Info.plist"
      EXPECTED_PROJECT="pasella-ledger"
      FALLBACK_PROJECT="pasella-ledger"
      ;;
    *)
      echo "error: Unknown SPAZAONE_ENVIRONMENT=${SPAZAONE_ENVIRONMENT}"
      exit 1
      ;;
  esac

  if [ ! -f "${SOURCE_PLIST}" ]; then
    echo "error: Missing Firebase configuration ${SOURCE_PLIST}"
    exit 1
  fi

  ACTUAL_PROJECT=$(/usr/libexec/PlistBuddy -c 'Print :PROJECT_ID' "${SOURCE_PLIST}")
  if [ "${ACTUAL_PROJECT}" != "${EXPECTED_PROJECT}" ] && \
     [ "${ACTUAL_PROJECT}" != "${FALLBACK_PROJECT}" ]; then
    echo "error: ${SPAZAONE_ENVIRONMENT} cannot use Firebase project ${ACTUAL_PROJECT}"
    exit 1
  fi

  DESTINATION="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GoogleService-Info.plist"
  /bin/mkdir -p "$(dirname "${DESTINATION}")"
  /bin/cp "${SOURCE_PLIST}" "${DESTINATION}"
SH

project.save

FileUtils.mkdir_p(SCHEME_DIR)
source_scheme = File.read(File.join(SCHEME_DIR, 'Runner.xcscheme'))
ENVIRONMENTS.each_key do |environment|
  scheme = source_scheme
           .gsub('buildConfiguration = "Debug"',
                 "buildConfiguration = \"Debug-#{environment}\"")
           .gsub('buildConfiguration = "Profile"',
                 "buildConfiguration = \"Profile-#{environment}\"")
           .gsub('buildConfiguration = "Release"',
                 "buildConfiguration = \"Release-#{environment}\"")
  File.write(File.join(SCHEME_DIR, "#{environment}.xcscheme"), scheme)
end

puts 'Configured SpazaOne iOS development and production environments.'
