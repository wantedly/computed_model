# ComputedModel

ComputedModel is a helper for building a read-only model (sometimes called a view)
from multiple sources of models.
It comes with batch loading and dependency resolution for better performance.

It is designed to be universal. It's as easy as pie to pull data from both
ActiveRecord and remote server (such as ActiveResource).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'computed_model'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install computed_model

## Usage

Include `ComputedModel` in your model class. You may also need an `attr_reader` for the primary key.

```ruby
class User
  attr_reader :id

  include ComputedModel

  def initialize(id)
    @id = id
  end
end
```

They your model class will be able to define the two kinds of special attributes:

- **Loaded attributes** for external data. You define batch loading strategies for loaded attributes.
- **Computed attributes** for data derived from loaded attributes or other computed attributes.
  You define a usual `def` with special dependency annotations.

## Loaded attributes

Use `ComputedModel::ClassMethods#define_loader` to define loaded attributes.

```ruby
# Example: pulling data from ActiveRecord
define_loader :raw_user do |users, subdeps, **options|
  user_ids = users.map(&:id)
  raw_users = RawUser.where(id: user_ids).preload(subdeps).index_by(&:id)
  users.each do |user|
    # Even if it doesn't exist, you must explicitly assign nil to the field.
    user.raw_user = raw_users[user.id]
  end
end
```

The first argument to the block is an array of the model instances.
The loader's job is to assign something to the corresponding field of each instance.

The second argument to the block is called a "sub-dependency".
The value of `subdeps` is an array, but further details are up to you
(it's just a verbatim copy of what you pass to `ComputedModel::ClassMethods#dependency`).
It's customary to take something ActiveRecord's `preload` accepts.

The keyword arguments are also a verbatim copy of what you pass to `ComputedModel::ClassMethods#bulk_load_and_compute`.

## Computed attributes

Use `ComputedModel::ClassMethods#computed` and `#dependency` to define computed attributes.

```ruby
dependency raw_user: [:name], user_music_info: [:latest]
computed def name_with_playing_music
  if user_music_info.latest&.playing?
    "#{user.name} (Now playing: #{user_music_info.latest.name})"
  else
    user.name
  end
end
```

## Batch loading

Once you defined loaded and computed attributes, you can batch-load them using `ComputedModel::ClassMethods#bulk_load_and_compute`.

Typically you need to create a wrapper for the batch loader like:

```ruby
def self.list(ids, with:)
  # Create placeholder objects.
  objs = ids.map { |id| User.new(id) }
  # Batch-load attributes into the objects.
  bulk_load_and_compute(objs, Array(with) + [:raw_user])
  # Reject objects without primary model.
  objs.reject! { |u| u.raw_user.nil? }
  objs
end
```

They you can retrieve users with only a specified attributes in a batch:

```ruby
users = User.list([1, 2, 3], with: [:name, :name_with_playing_music, :premium_user])
```

## License

This library is distributed under MIT license.

Copyright (c) 2020 Masaki Hara
Copyright (c) 2020 Wantedly, Inc.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/qnighy/computed_model.
