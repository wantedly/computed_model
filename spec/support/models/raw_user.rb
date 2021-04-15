# frozen_string_literal: true

require 'support/models/application_record'

class RawUser < ApplicationRecord
  self.table_name = "users"
end
