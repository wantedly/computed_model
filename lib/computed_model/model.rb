# frozen_string_literal: true

# A mixin for batch-loadable compound models.
#
# @example typical structure of a computed model
#   class User
#     include ComputedModel::Model
#
#     attr_reader :id
#     def initialize(id)
#       @id = id
#     end
#
#     define_loader do ... end
#
#     dependency :foo, :bar
#     computed def something ... end
#   end
module ComputedModel::Model
  # A set of class methods for {ComputedModel}. Automatically included to the
  # singleton class when you include {ComputedModel::Model}.
  module ClassMethods
    # Declares the dependency of a computed attribute. See {#computed} too.
    #
    # @param deps [Array<Symbol, Hash{Symbol=>Array}>]
    #   Dependency description. If a symbol `:foo` is given,
    #   it's interpreted as `{ foo: [] }`.
    #   When the same symbol occurs multiple times, the array is concatenated.
    #   The contents of the array (called "sub-dependency") is treated opaquely
    #   by the `computed_model` gem. It is up to the user to design the format
    #   of sub-dependencies.
    # @return [void]
    #
    # @example declaring dependencies
    #   dependency :user, :user_external_resource
    #   computed def something
    #     # Use user and user_external_resource ...
    #   end
    #
    # @example declaring dependencies with sub-dependencies
    #   dependency user: [:user_names, :premium], user_external_resource: [:received_stars]
    #   computed def something
    #     # Use user and user_external_resource ...
    #   end
    def dependency(*deps)
      @__computed_model_next_dependency ||= []
      @__computed_model_next_dependency.push(*deps)
    end

    # Declares a computed attribute. See {#dependency} too.
    #
    # @param meth_name [Symbol] a method name to promote to a computed attribute.
    #   Typically used in the form of `computed def ...`.
    # @return [Symbol] passes through the argument.
    #
    # @example define a field which is calculated from loaded models
    #   dependency :user, :user_external_resource
    #   computed def something
    #     # Use user and user_external_resource ...
    #   end
    def computed(meth_name)
      var_name = :"@#{meth_name}"
      meth_name_orig = :"#{meth_name}_orig"
      compute_meth_name = :"compute_#{meth_name}"

      @__computed_model_graph << ComputedModel::DepGraph::Node.new(:computed, meth_name, @__computed_model_next_dependency)
      remove_instance_variable(:@__computed_model_next_dependency) if defined?(@__computed_model_next_dependency)

      alias_method meth_name_orig, meth_name
      define_method(meth_name) do
        raise ComputedModel::NotLoaded, "the field #{meth_name} is not loaded" unless instance_variable_defined?(var_name)
        instance_variable_get(var_name)
      end
      define_method(compute_meth_name) do
        instance_variable_set(var_name, send(meth_name_orig))
      end
      if public_method_defined?(meth_name_orig)
        public meth_name
      elsif protected_method_defined?(meth_name_orig)
        protected meth_name
      elsif private_method_defined?(meth_name_orig)
        private meth_name
      end

      meth_name
    end

    # A shorthand for simple computed attributes.
    #
    # Use {#computed} for more complex definition.
    #
    # @param methods [Array<Symbol>] method names to delegate
    # @param to [Symbol] which attribute to delegate the methods to.
    #   This parameter is used for the dependency declaration too.
    # @param allow_nil [nil, Boolean] If `true`,
    #   nil receivers are is ignored, and nil is returned instead.
    # @param prefix [nil, Symbol] A prefix for the delegating method name.
    # @param include_subdeps [nil, Boolean] If `true`,
    #   sub-dependencies are also included.
    # @return [void]
    #
    # @example delegate name from raw_user
    #   delegate_dependency :name, to: :raw_user
    #
    # @example delegate name from raw_user, but expose as user_name
    #   delegate_dependency :name, to: :raw_user, prefix: :user
    def delegate_dependency(*methods, to:, allow_nil: nil, prefix: nil, include_subdeps: nil)
      method_prefix = prefix ? "#{prefix}_" : ""
      methods.each do |meth_name|
        pmeth_name = :"#{method_prefix}#{meth_name}"
        if include_subdeps
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

    # Declares a loaded attribute. See {#dependency} and {#define_primary_loader} too.
    #
    # `define_loader :foo do ... end` generates a reader `foo` and a writer `foo=`.
    # The writer is only meant to be used in the loader.
    #
    # The responsibility of loader is to call `foo=` for all the given objects.
    #
    # @param meth_name [Symbol] the name of the loaded attribute.
    # @param key [Proc] The proc to collect keys.
    # @return [void]
    # @yield [keys, subdeps, **options]
    # @yieldparam objects [Array] The ids of the loaded attributes.
    # @yieldparam subdeps [Hash] sub-dependencies
    # @yieldparam options [Hash] A verbatim copy of what is passed to {#bulk_load_and_compute}.
    # @yieldreturn [Hash]
    #
    # @example define a loader for ActiveRecord-based models
    #   define_loader :user_aux_data, key: -> { id } do |user_ids, subdeps, **options|
    #     UserAuxData.where(user_id: user_ids).preload(subdeps).group_by(&:id)
    #   end
    def define_loader(meth_name, key:, &block)
      remove_instance_variable(:@__computed_model_next_dependency) if defined?(@__computed_model_next_dependency)
      raise ArgumentError, "No block given" unless block

      var_name = :"@#{meth_name}"
      loader_name = :"__computed_model_load_#{meth_name}"
      writer_name = :"#{meth_name}="

      @__computed_model_graph << ComputedModel::DepGraph::Node.new(:loaded, meth_name, {})
      define_singleton_method(loader_name) do |objs, subdeps, **options|
        keys = objs.map { |o| o.instance_exec(&key) }
        subobj_by_key = block.call(keys, subdeps, **options)
        objs.zip(keys) do |obj, key|
          obj.send(writer_name, subobj_by_key[key])
        end
      end

      define_method(meth_name) do
        raise NotLoaded, "the field #{meth_name} is not loaded" unless instance_variable_defined?(var_name)
        instance_variable_get(var_name)
      end
      attr_writer meth_name
    end

    # Declares a primary attribute. See {#define_loader} and {#dependency} too.
    #
    # `define_primary_loader :foo do ... end` generates a reader `foo` and
    # a writer `foo=`.
    # The writer is only meant to be used in the loader.
    #
    # The responsibility of the primary loader is to list up all the relevant
    # primary models, and initialize instances of the subclass of ComputedModel
    # with `@foo` set to the primary model which is just being found.
    #
    # @param meth_name [Symbol] the name of the loaded attribute.
    # @return [void]
    # @yield [**options]
    # @yieldparam options [Hash] A verbatim copy of what is passed to {#bulk_load_and_compute}.
    # @yieldreturn [void]
    #
    # @example define a loader for ActiveRecord-based models
    #   define_loader :raw_user do |users, subdeps, **options|
    #     user_ids = users.map(&:id)
    #     raw_users = RawUser.where(id: user_ids).preload(subdeps).index_by(&:id)
    #     users.each do |user|
    #       # Even if it doesn't exist, you must explicitly assign nil to the field.
    #       user.raw_user = raw_users[user.id]
    #     end
    #   end
    def define_primary_loader(meth_name, &block)
      if defined?(@__computed_model_next_dependency)
        remove_instance_variable(:@__computed_model_next_dependency)
        raise ArgumentError, 'primary field cannot have a dependency'
      end
      raise ArgumentError, "No block given" unless block

      var_name = :"@#{meth_name}"
      loader_name = :"__computed_model_enumerate_#{meth_name}"

      @__computed_model_graph << ComputedModel::DepGraph::Node.new(:primary, meth_name, {})
      define_singleton_method(loader_name) do |subdeps, **options|
        block.call(subdeps, **options)
      end

      define_method(meth_name) do
        raise NotLoaded, "the field #{meth_name} is not loaded" unless instance_variable_defined?(var_name)
        instance_variable_get(var_name)
      end
      attr_writer meth_name
    end

    # The core routine for batch-loading.
    #
    # @param deps [Array<Symbol, Hash{Symbol=>Array}>] A set of dependencies.
    # @param options [Hash] An arbitrary hash to pass to loaders
    #   defined by {#define_loader}.
    # @return [Array<Object>] The array of the requested models.
    #   Based on what the primary loader returns.
    def bulk_load_and_compute(deps, **options)
      objs = nil
      plan = @__computed_model_graph.plan(deps)
      plan.load_order.each do |dep_name|
        case @__computed_model_graph[dep_name].type
        when :primary
          loader_name = :"__computed_model_enumerate_#{dep_name}"
          objs = send(loader_name, plan.subdeps_hash[dep_name], **options)
        when :computed
          objs.each do |obj|
            obj.send(:"compute_#{dep_name}")
          end
        when :loaded
          loader_name = :"__computed_model_load_#{dep_name}"
          send(loader_name, objs, plan.subdeps_hash[dep_name], **options)
        else
          raise "No dependency info for #{self}##{dep_name}"
        end
      end

      objs
    end
  end

  def self.included(klass)
    super
    klass.extend ClassMethods
    klass.instance_variable_set(:@__computed_model_graph, ComputedModel::DepGraph.new)
  end
end
