# frozen_string_literal: true

require 'support/models/application_record'

class RawBook < ApplicationRecord
  self.table_name = "books"
end
