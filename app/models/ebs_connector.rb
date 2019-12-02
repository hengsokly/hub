class EbsConnector < Connector
  include Entity

  store_accessor :settings, :url, :access_token
  after_initialize :initialize_defaults, :if => :new_record?

  def human_type
    "Ebs"
  end

  def properties(context)
    {"milestones" => Milestones.new(self)}
  end

  def has_events?
    false
  end

  def get(relative_uri)
    RestClient.get "#{self.url}/api/v1/#{relative_uri}", auth_headers
  end

  def get_json(relative_uri)
    JSON.parse get(relative_uri)
  end

  def auth_headers
    {"Authorization" => "Token #{access_token}"}
  end

  private

  def initialize_defaults
    self.url ||= "https://localhost:3000"
  end

  class Milestones
    include EntitySet

    def initialize(parent)
      @parent = parent
    end

    def path
      "milestones"
    end

    def label
      "Milestones"
    end

    def query(filters, context, options)
      milestones = connector.get_json 'milestones'
      milestones.map! { |milestone| Milestone.new(self, milestone['id'], milestone) }
      { items: milestones }
    end

    def find_entity(id, context)
      Milestone.new(self, id)
    end
  end

  class Milestone
    include Entity
    attr_reader :id

    def initialize(parent, id, milestone={})
      @parent = parent
      @id = id
      @milestone = milestone
    end

    def label
      @milestone['name']
    end

    def sub_path
      id
    end

    def milestone
      @milestone ||= connector.get_json("milestones/#{@id}")
    end

    def properties(context)
      {
        "id" => SimpleProperty.id(@id),
        "name" => SimpleProperty.name('')
      }
    end

    def actions(context)
      {
        "insert" => InsertAction.new(self)
      }
    end
  end

  class InsertAction
    include Action

    def initialize(parent)
      @parent = parent
    end

    def label
      "Insert"
    end

    def sub_path
      "insert"
    end

    # request to get milestone fields
    def args(context)
      res = connector.get_json "milestones/#{parent.id}/fields"
      fields = res['fields'].concat(res['meta']['extra_fields'])
      obj = {}

      fields.each do |field|
        obj[field['code']] = {
          type: field['type'],
          label: field['label']
        }
      end

      obj
    end

    # request to send data for inserting field_value
    def invoke(args, context)
      res = connector.get_json "milestones/#{parent.id}/fields"
      fields = res['fields'].select { |field| field['id'].present? }
      field_values = fields.map do |field|
        { field_id: field['id'], field_code: field['code'], value: args[field['code']] }
      end

      milestone = res['meta']['milestone']
      payload = milestone['is_default'] ? { event: { event_type_id: args['event_type_id'], field_values_attributes: field_values } } : { event_milestone: { milestone_id: milestone['id'], event_uuid: args['event_uuid'], field_values_attributes: field_values } }
      endpoint = milestone['is_default'] ? 'events' : 'event_milestones'
      url = "#{connector.url}/api/v1/#{endpoint}"
      headers = connector.auth_headers.merge({ content_type: :json, accept: :json })

      RestClient.post(url, payload.to_json, headers)
    end
  end
end
