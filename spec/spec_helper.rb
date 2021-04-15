# frozen_string_literal: true

require "bundler/setup"
require 'factory_bot'
require "computed_model"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include FactoryBot::Syntax::Methods

  config.before(:suite) do
    FactoryBot.find_definitions
  end

  config.before(:suite) do
    require 'support/db/connection'
    ActiveRecord::Base.logger.level = Logger::WARN
    require 'support/db/schema'
  end
end
