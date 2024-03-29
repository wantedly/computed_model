# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "computed_model/version"

Gem::Specification.new do |spec|
  spec.name          = "computed_model"
  spec.version       = ComputedModel::VERSION
  spec.authors       = ["Masaki Hara", "Masayuki Izumi", "Wantedly, Inc."]
  spec.email         = ["ackie.h.gmai@gmail.com", "m@izum.in", "dev@wantedly.com"]

  spec.summary       = %q{Batch loader with dependency resolution and computed fields}
  spec.description   = <<~DSC
    ComputedModel is a helper for building a read-only model (sometimes called a view)
    from multiple sources of models.
    It comes with batch loading and dependency resolution for better performance.

    It is designed to be universal. It's as easy as pie to pull data from both
    ActiveRecord and remote server (such as ActiveResource).
  DSC
  spec.homepage      = "https://github.com/wantedly/computed_model"
  spec.licenses      = ['MIT']

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/wantedly/computed_model"
  spec.metadata["changelog_uri"] = "https://github.com/wantedly/computed_model/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # For ActiveSupport::Concern
  spec.add_development_dependency "activesupport"

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "activerecord", "~> 7.0"
  spec.add_development_dependency "sqlite3", "~> 1.4"
  spec.add_development_dependency "factory_bot", "~> 6.1"
  spec.add_development_dependency "simplecov", "~> 0.21.2"
  spec.add_development_dependency "simplecov-lcov", "~> 0.8.0"
end
