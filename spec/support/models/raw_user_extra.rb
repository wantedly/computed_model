# frozen_string_literal: true

require 'support/models/application_record'

class RawUserExtra < ApplicationRecord
  self.table_name = "user_extras"
end
