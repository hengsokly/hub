module EntitySet
  extend ActiveSupport::Concern

  attr_reader :parent

  abstract :path, :label
  def reflect_entities(user)
    select({}, user, page: 1, page_size: 1000)
  end

  def self.included(mod)
    mod.delegate :connector, to: :parent unless mod.method_defined?(:connector)
  end

  def lookup(path, user)
    return self if path.empty?
    entity_id = path.shift

    case entity_id
    when "$actions"
      ActionsNode.new(self).lookup(path, user)
    when "$events"
      EventsNode.new(self).lookup(path, user)
    else
      find_entity(entity_id, user).lookup(path, user)
    end
  end

  def reflect_path
    path
  end

  def actions(user)
    actions = Hash.new
    if protocols.include? :select
      actions["select"] = SelectAction.new(self)
    end
    actions.presence
  end

  def events
  end

  module ClassMethods
    def protocol(*methods)
      protocols.concat methods
    end
    def protocols
      @protocols ||= Array.new
    end

    def filter_by(*methods)
      filters.concat methods
    end
    def filters
      @filters ||= Array.new
    end
  end

  def protocols
    self.class.protocols
  end

  def filters
    self.class.filters
  end

  abstract def select(filters, current_user, options)
  end

  def entity_properties
  end

  def reflect_property reflect_url_proc, user
    reflection = {}
    reflection[:label] = label
    reflection[:type] = node_type
    reflection[:path] = path
    reflection[:reflect_url] = reflect_url_proc.call(reflect_path) if reflect_path
    if entity_properties
      reflection[:entity_definition] = {}
      reflection[:entity_definition][:properties] = SimpleProperty.reflect reflect_url_proc, entity_properties, user
    end
    reflection[:protocol] = protocols unless protocols.empty?
    reflection
  end

  def reflect(reflect_url_proc, user)
    reflection = reflect_property reflect_url_proc, user
    if e = reflect_entities(user)
      reflection[:entities] = e.map { |entity| entity.reflect_property(reflect_url_proc, user) }
    end
    if a = actions(user)
      reflection[:actions] = SimpleProperty.reflect reflect_url_proc, a, user
    end
    if e = events
      reflection[:events] = SimpleProperty.reflect reflect_url_proc, e, user
    end
      reflection
  end

  def node_type
    :entity_set
  end

  class SelectAction
    include Action

    def initialize(parent)
      @parent = parent
    end

    def label
      "Select"
    end

    def sub_path
      "select"
    end

    def args(user)
      SimpleProperty.reflect nil, (@parent.entity_properties.select do |key, property|
        @parent.filters.include? key
      end), user
    end

    def invoke(args, user)
      filter = args.delete(:filter)
      @parent.select filter, current_user, args
    end
  end
end
