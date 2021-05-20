FactoryBot.define do
  factory :raw_user_extra do
    token { "abcdef0123456789" }
    id { create(:raw_user).id }
  end
end
