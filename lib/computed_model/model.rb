# frozen_string_literal: true

require 'active_support/concern'

# A mixin for batch-loadable compound models. This is the main API of ComputedModel.
#
# See {ComputedModel::Model::ClassMethods} for methods you can use in the including classes.
#
# @example
#   require 'computed_model'
#
#   # Consider them external sources (ActiveRecord or resources obtained via HTTP)
#   RawUser = Struct.new(:id, :name, :title)
#   Preference = Struct.new(:user_id, :name_public)
#
#   class User
#     include ComputedModel::Model
#
#     attr_reader :id
#     def initialize(raw_user)
#       @id = raw_user.id
#       @raw_user = raw_user
#     end
#
#     def self.list(ids, with:)
#       bulk_load_and_compute(Array(with), ids: ids)
#     end
#
#     define_primary_loader :raw_user do |_subfields, ids:, **|
#       # In ActiveRecord:
#       # raw_users = RawUser.where(id: ids).to_a
#       raw_users = [
#         RawUser.new(1, "Tanaka Taro", "Mr. "),
#         RawUser.new(2, "Yamada Hanako", "Dr. "),
#       ].filter { |u| ids.include?(u.id) }
#       raw_users.map { |u| User.new(u) }
#     end
#
#     define_loader :preference, key: -> { id } do |user_ids, _subfields, **|
#       # In ActiveRecord:
#       # Preference.where(user_id: user_ids).index_by(&:user_id)
#       {
#         1 => Preference.new(1, true),
#         2 => Preference.new(2, false),
#       }.filter { |k, _v| user_ids.include?(k) }
#     end
#
#     delegate_dependency :name, to: :raw_user
#     delegate_dependency :title, to: :raw_user
#     delegate_dependency :name_public, to: :preference
#
#     dependency :name, :name_public
#     computed def public_name
#       name_public ? name : "Anonymous"
#     end
#
#     dependency :public_name, :title
#     computed def public_name_with_title
#       "#{title}#{public_name}"
#     end
#   end
#
#   # You can only access the field you requested ahead of time
#   users = User.list([1, 2], with: [:public_name_with_title])
#   users.map(&:public_name_with_title) # => ["Mr. Tanaka Taro", "Dr. Anonymous"]
#   users.map(&:public_name) # => error (ForbiddenDependency)
#
#   users = User.list([1, 2], with: [:public_name_with_title, :public_name])
#   users.map(&:public_name_with_title) # => ["Mr. Tanaka Taro", "Dr. Anonymous"]
#   users.map(&:public_name) # => ["Tanaka Taro", "Anonymous"]
#
#   # In this case, preference will not be loaded.
#   users = User.list([1, 2], with: [:title])
#   users.map(&:title) # => ["Mr. ", "Dr. "]

module ComputedModel::Model
  extend ActiveSupport::Concern

  # A set of class methods for {ComputedModel::Model}. Automatically included to the
  # singleton class when you include {ComputedModel::Model}.
  #
  # See {ComputedModel::Model} for examples.
  module ClassMethods
    # Declares the dependency of a computed field.
    # Normally a call to this method will be followed by a call to {#computed} (or {#define_loader}).
    #
    # @param deps [Array<Symbol, Hash{Symbol=>Array, Object}>]
    #   Dependency list. Most simply an array of Symbols (field names).
    #
    #   It also accepts Hashes. In this case, the keys of the hashes are field names.
    #   The values are called subfield selectors.
    #
    #   Subfield selector is one of the following:
    #
    #   - nil, true, or false (constant condition)
    #   - `#call`able objects accepting one argument (dynamic selector)
    #   - other objects (static selector)
    #
    #   Multiple subfield selectors can be specified at once as an array.
    #
    #   See CONCEPTS.md for the more detailed description of dependency formats.
    # @return [void]
    # @raise [RuntimeError] if the dependency list contains values other than Symbol or Hash
    #
    # @example declaring dependencies
    #   dependency :user, :user_external_resource
    #   computed def something
    #     # Use user and user_external_resource ...
    #   end
    #
    # @example declaring dependencies with subfield selectors
    #   dependency user: [:user_names, :premium], user_external_resource: [:received_stars]
    #   computed def something
    #     # Use user and user_external_resource ...
    #   end
    #
    # @example declaring dynamic dependencies
    #   dependency user: -> (subfields) { "..." }
    #   computed def something
    #     # Use user ...
    #   end
    def dependency(*deps)
      @__computed_model_next_dependency ||= []
      @__computed_model_next_dependency.push(*deps)
    end

    # Declares a computed field. Normally it follows a call to {#dependency}.
    #
    # @param meth_name [Symbol] a method name to promote to a computed field.
    #   Typically used in the form of `computed def ...`.
    # @return [Symbol] the first argument as-is.
    #
    # @example define a field which is calculated from other fields
    #   dependency :user, :user_external_resource
    #   computed def something
    #     # Use user and user_external_resource ...
    #   end
    def computed(meth_name)
      var_name = :"@#{meth_name}"
      meth_name_orig = :"#{meth_name}_orig"
      compute_meth_name = :"compute_#{meth_name}"

      __computed_model_graph << ComputedModel::DepGraph::Node.new(:computed, meth_name, @__computed_model_next_dependency)
      remove_instance_variable(:@__computed_model_next_dependency) if defined?(@__computed_model_next_dependency)

      alias_method meth_name_orig, meth_name
      define_method(meth_name) do
        raise ComputedModel::NotLoaded, "the field #{meth_name} is not loaded" unless instance_variable_defined?(var_name)

        __computed_model_check_availability(meth_name)
        instance_variable_get(var_name)
      end
      define_method(compute_meth_name) do
        @__computed_model_stack << @__computed_model_plan[meth_name]
        begin
          instance_variable_set(var_name, send(meth_name_orig))
        ensure
          @__computed_model_stack.pop
        end
      end
      if public_method_defined?(meth_name_orig)
        public meth_name
      elsif protected_method_defined?(meth_name_orig)
        protected meth_name
      else # elsif private_method_defined?(meth_name_orig)
        private meth_name
      end

      meth_name
    end

    # A shorthand for simple computed field.
    #
    # Use {#computed} for more complex definition.
    #
    # @param methods [Array<Symbol>] method names to delegate
    # @param to [Symbol] which field to delegate the methods to.
    #   This parameter is used for the dependency declaration too.
    # @param allow_nil [nil, Boolean] If `true`,
    #   nil receivers are ignored, and nil is returned instead.
    # @param prefix [nil, Symbol] A prefix for the delegating method name.
    # @param include_subfields [nil, Boolean] If `true`,
    #   it includes meth_name as a subfield selector.
    # @return [void]
    #
    # @example delegate name from raw_user
    #   delegate_dependency :name, to: :raw_user
    #
    # @example delegate name from raw_user, but expose as user_name
    #   delegate_dependency :name, to: :raw_user, prefix: :user
    def delegate_dependency(*methods, to:, allow_nil: nil, prefix: nil, include_subfields: nil)
      method_prefix = prefix ? "#{prefix}_" : ""
      methods.each do |meth_name|
        pmeth_name = :"#{method_prefix}#{meth_name}"
        if include_subfields
          dependency to=>meth_name
        else
          dependency to
        end
        if allow_nil
          define_method(pmeth_name) do
            send(to)&.public_send(meth_name)
          end
        else
          define_method(pmeth_name) do
            send(to).public_send(meth_name)
          end
        end
        computed pmeth_name
      end
    end

    # Declares a loaded field. See {#dependency} and {#define_primary_loader} too.
    #
    # `define_loader :foo do ... end` generates a reader `foo` and a writer `foo=`.
    # The writer only exists for historical reasons.
    #
    # The block passed to `define_loader` is called a loader.
    # Loader should return a hash containing field values.
    #
    # - The keys of the hash must match `record.instance_exec(&key)`.
    # - The values of the hash represents the field values.
    #
    # @param meth_name [Symbol] the name of the loaded field.
    # @param key [Proc] The proc to collect keys. In the proc, `self` evaluates to the record instance.
    #   Typically `-> { id }`.
    # @return [void]
    # @raise [ArgumentError] if no block is given
    # @yield [keys, subfields, **options]
    # @yieldparam keys [Array] the array of keys.
    # @yieldparam subfields [Array] subfield selectors
    # @yieldparam options [Hash] the batch-loading parameters.
    #   The keyword arguments to {#bulk_load_and_compute} will be passed down here as-is.
    # @yieldreturn [Hash] a hash containing field values.
    #
    # @example define a loader for ActiveRecord-based models
    #   define_loader :user_aux_data, key: -> { id } do |user_ids, subfields, **options|
    #     UserAuxData.where(user_id: user_ids).preload(subfields).group_by(&:id)
    #   end
    def define_loader(meth_name, key:, &block)
      raise ArgumentError, "No block given" unless block

      var_name = :"@#{meth_name}"
      loader_name = :"__computed_model_load_#{meth_name}"
      writer_name = :"#{meth_name}="

      __computed_model_graph << ComputedModel::DepGraph::Node.new(:loaded, meth_name, @__computed_model_next_dependency)
      remove_instance_variable(:@__computed_model_next_dependency) if defined?(@__computed_model_next_dependency)
      define_singleton_method(loader_name) do |objs, subfields, **options|
        keys = objs.map { |o| o.instance_exec(&key) }
        field_values = block.call(keys, subfields, **options)
        objs.zip(keys) do |obj, key|
          obj.send(writer_name, field_values[key])
        end
      end

      define_method(meth_name) do
        raise ComputedModel::NotLoaded, "the field #{meth_name} is not loaded" unless instance_variable_defined?(var_name)

        __computed_model_check_availability(meth_name)
        instance_variable_get(var_name)
      end
      # TODO: remove writer?
      attr_writer meth_name
    end

    # Declares a primary field. See {#define_loader} and {#dependency} too.
    # ComputedModel should have exactly one primary field.
    #
    # `define_primary_loader :foo do ... end` generates a reader `foo` and
    # a writer `foo=`.
    # The writer only exists for historical reasons.
    #
    # The block passed to `define_loader` is called a primary loader.
    # The primary loader's responsibility is batch loading + enumeration (search).
    # In contrast to {#define_loader}, where a hash of field values are returned,
    # the primary loader should return an array of record objects.
    #
    # For example, if your class is `User`, the primary loader must return `Array<User>`.
    #
    # Additionally, the primary loader must initialize all the record objects
    # so that the same instance variable `@#{meth_name}` is set.
    #
    # @param meth_name [Symbol] the name of the loaded field.
    # @return [Array] an array of record objects.
    # @raise [ArgumentError] if no block is given
    # @raise [ArgumentError] if it follows a {#dependency} declaration
    # @yield [subfields, **options]
    # @yieldparam subfields [Array] subfield selectors
    # @yieldparam options [Hash] the batch-loading parameters.
    #   The keyword arguments to {#bulk_load_and_compute} will be passed down here as-is.
    # @yieldreturn [void]
    #
    # @example define a primary loader for ActiveRecord-based models
    #   class User
    #     include ComputedModel::Model
    #
    #     def initialize(raw_user)
    #       # @raw_user must match the name of the primary loader
    #       @raw_user = raw_user
    #     end
    #
    #     define_primary_loader :raw_user do |subfields, **options|
    #       raw_users = RawUser.where(id: user_ids).preload(subfields)
    #       # Create User instances
    #       raw_users.map { |raw_user| User.new(raw_user) }
    #     end
    #   end
    def define_primary_loader(meth_name, &block)
      # TODO: The current API requires the user to initialize a specific instance variable.
      # TODO: this design is a bit ugly.
      if defined?(@__computed_model_next_dependency)
        remove_instance_variable(:@__computed_model_next_dependency)
        raise ArgumentError, 'primary field cannot have a dependency'
      end
      raise ArgumentError, "No block given" unless block

      var_name = :"@#{meth_name}"
      loader_name = :"__computed_model_enumerate_#{meth_name}"

      __computed_model_graph << ComputedModel::DepGraph::Node.new(:primary, meth_name, {})
      define_singleton_method(loader_name) do |subfields, **options|
        block.call(subfields, **options)
      end

      define_method(meth_name) do
        raise ComputedModel::NotLoaded, "the field #{meth_name} is not loaded" unless instance_variable_defined?(var_name)

        __computed_model_check_availability(meth_name)
        instance_variable_get(var_name)
      end
      # TODO: remove writer?
      attr_writer meth_name
    end

    # The core routine for batch-loading.
    #
    # Each model class is expected to provide its own wrapper of this method. See CONCEPTS.md for examples.
    #
    # @param deps [Array<Symbol, Hash{Symbol=>Array, Object}>] dependency list. Same format as {#dependency}.
    #   See {ComputedModel.normalize_dependencies} too.
    # @param options [Hash] the batch-loading parameters.
    #   Passed down as-is to loaders ({#define_loader}) and the primary loader ({#define_primary_loader}).
    # @return [Array<Object>] The array of record objects, with requested fields filled in.
    # @raise [ComputedModel::CyclicDependency] if the graph has a cycle
    # @raise [ArgumentError] if the graph lacks a primary field
    # @raise [RuntimeError] if the graph has multiple primary fields
    # @raise [RuntimeError] if the graph has a dangling dependency (reference to an undefined field)
    def bulk_load_and_compute(deps, **options)
      objs = nil
      sorted = __computed_model_sorted_graph
      plan = sorted.plan(deps)
      plan.load_order.each do |node|
        case sorted.original[node.name].type
        when :primary
          loader_name = :"__computed_model_enumerate_#{node.name}"
          objs = send(loader_name, ComputedModel.filter_subfields(node.subfields), **options)
          dummy_toplevel_node = ComputedModel::Plan::Node.new(nil, plan.toplevel, nil)
          objs.each do |obj|
            obj.instance_variable_set(:@__computed_model_plan, plan)
            obj.instance_variable_set(:@__computed_model_stack, [dummy_toplevel_node])
          end
        when :loaded
          loader_name = :"__computed_model_load_#{node.name}"
          objs.each do |obj|
            obj.instance_variable_get(:@__computed_model_stack) << node
          end
          begin
            send(loader_name, objs, ComputedModel.filter_subfields(node.subfields), **options)
          ensure
            objs.each do |obj|
              obj.instance_variable_get(:@__computed_model_stack).pop
            end
          end
        else # when :computed
          objs.each do |obj|
            obj.send(:"compute_#{node.name}")
          end
        end
      end

      objs
    end

    # Verifies the dependency graph for errors. Useful for early error detection.
    # It also prevents concurrency issues.
    #
    # Place it after all the relevant declarations. Otherwise a mysterious bug may occur.
    #
    # @return [void]
    # @raise [ComputedModel::CyclicDependency] if the graph has a cycle
    # @raise [ArgumentError] if the graph lacks a primary field
    # @raise [RuntimeError] if the graph has multiple primary fields
    # @raise [RuntimeError] if the graph has a dangling dependency (reference to an undefined field)
    # @example
    #   class User
    #     computed def foo
    #       # ...
    #     end
    #
    #     # ...
    #
    #     verify_dependencies
    #   end
    def verify_dependencies
      __computed_model_sorted_graph
      nil
    end

    # @return [ComputedModel::DepGraph::Sorted]
    private def __computed_model_sorted_graph
      @__computed_model_sorted_graph ||= __computed_model_merged_graph.tsort
    end

    # @return [ComputedModel::DepGraph]
    private def __computed_model_merged_graph
      graphs = ancestors.reverse.map { |m| m.respond_to?(:__computed_model_graph, true) ? m.send(:__computed_model_graph) : nil }.compact
      ComputedModel::DepGraph.merge(graphs)
    end

    # @return [ComputedModel::DepGraph]
    private def __computed_model_graph
      @__computed_model_graph ||= ComputedModel::DepGraph.new
    end
  end

  # Returns dependency of the currently computing field,
  # or the toplevel dependency if called outside of computed fields.
  # @return [Set<Symbol>]
  def current_deps
    @__computed_model_stack.last.deps
  end

  # Returns subfield selectors passed to the currently computing field,
  # or nil if called outside of computed fields.
  # @return [ComputedModel::NormalizableArray, nil]
  def current_subfields
    @__computed_model_stack.last.subfields
  end

  # @param name [Symbol]
  private def __computed_model_check_availability(name)
    return if @__computed_model_stack.last.deps.include?(name)

    raise ComputedModel::ForbiddenDependency, "Not a direct dependency: #{name}"
  end
end
