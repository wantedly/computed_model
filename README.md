# ComputedModel

ComputedModel is a helper for building a read-only model (sometimes called a view)
from multiple sources of models.
It comes with batch loading and dependency resolution for better performance.

It is designed to be universal. It's as easy as pie to pull data from both
ActiveRecord and remote server (such as ActiveResource).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'computed_model', '~> 0.1.1'
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
  - Among them, there is a special **primary model** for listing up the models from certain criteria.
- **Computed attributes** for data derived from loaded attributes or other computed attributes.
  You define a usual `def` with special dependency annotations.

## Loaded attributes

Use `ComputedModel::ClassMethods#define_primary_loader`
or `ComputedModel::ClassMethods#define_loader` to define loaded attributes.

```ruby
# Create a User instance
def initialize(raw_user)
  @id = raw_user.id
  @raw_user = raw_user
end

# Example: pulling data from ActiveRecord
define_primary_loader :raw_user do |subdeps, ids:, **options|
  RawUser.where(id: ids).preload(subdeps).map { |raw_user| User.new(raw_user) }
end

# Example: pulling auxiliary data from ActiveRecord
define_loader :user_aux_data do |users, subdeps, **options|
  user_ids = users.map(&:id)
  user_aux_data = UserAuxData.where(user_id: user_ids).preload(subdeps).group_by(&:id)
  users.each do |user|
    user.user_aux_data = user_aux_data[user.id]
  end
end
```

### `define_primary_loader`

At most one primary loader can be defined on a model class.

The primary loader's job is to list up models from user-defined criteria, along with
requested data loaded to the primary attribute.

Search criteria can be passed as a keyword argument to `bulk_list_and_compute`
and it will be passed to the loader as-is.

Most typically you receive `ids`, an array of integers, and use it like
`.where(id: ids)`. Instead you may want to accept a non-primary-key criterion
such as `group_ids` and `.where(group_id: group_ids)`.

The loader must return an array of instances of the model being defined.
Each instance must have the primary attribute assigned at that time.
In the example above, the block for `define_primary_loader :raw_user`
must return an array of `User`s, each of which already have `@raw_user`.

### `define_loader`

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

Once you defined loaded and computed attributes, you can batch-load them using `ComputedModel::ClassMethods#bulk_list_and_compute`.

Typically you need to create a wrapper for the batch loader like:

```ruby
def self.list(ids, with:)
  bulk_list_and_compute(Array(with), ids: ids)
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

Bug reports and pull requests are welcome on GitHub at https://github.com/wantedly/computed_model.
