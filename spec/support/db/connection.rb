# frozen_string_literal: true

require 'active_record'

ActiveRecord::Base.logger = Logger.new(STDERR)

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
