FactoryBot.define do
  factory :raw_user do
    sequence(:name) { |n| "User #{n}"}
  end
end
