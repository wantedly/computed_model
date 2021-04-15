require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec

namespace :db do
  namespace :schema do
    task :dump do
      $LOAD_PATH.push(File.join(__dir__, 'spec'))
      require 'active_record'
      require 'support/db/connection'
      require 'support/db/schema'
      File.open(File.join(__dir__, 'spec/support/db/schema.rb'), 'w:utf-8') do |file|
        ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection, file)
      end
    end
  end
end
