class DeathRecord < ApplicationRecord
  audited
  belongs_to :workflow, class_name: 'Workflow'
  belongs_to :owner, class_name: 'User'
  belongs_to :creator, class_name: 'User'
  belongs_to :step_flow
  has_one :step_status
  has_many :step_contents
  has_many :step_histories
  has_many :comments
  has_one :user_token
  has_one :registration
  has_one :death_certificate # TODO: eventually we'll likely want more than one with versioning

  # Return the StepFlows (in order) that make up this Workflow.
  def step_flows
    self.workflow.step_flows
  end

  # Builds a flat representation of this death records contents.
  def build_contents
    # Merge the array of hashes into one.
    flatten_hash = Hash[*step_contents.collect(&:contents).collect{|h| h.to_a}.flatten]
    # Create a flat hash structure
    Hash.to_dotted_hash flatten_hash
  end

  # Given a dot notation flat hash, this will break out the flat hash into the correct "steps"
  # Returns a hash of steps and the parameters that match the step's schema.
  def separate_step_contents(flat_hash)
    step_contents_hash = {}
    nested_hash = Hash.to_nested_hash flat_hash
    self.steps.each do |step|
      step_contents_hash[step.name] = nested_hash.slice(*get_params_for_step(step))
    end
    step_contents_hash
  end

  # Return the Steps (in order) that make up this Workflow.
  def steps
    step_flows.collect(&:current_step)
  end

  # Returns a hash of all allowed params for this DeathRecord.
  def whitelist
    steps.collect(&:whitelist).flatten.reduce({}, :merge)
  end

  # Determines if this DeathRecord can increment its current Step.
  def can_increment_step
    !step_flow.next_step.nil?
  end

  # Returns the next Step in this DeathRecords workflow.
  def next_step
    self.step_flow.next_step if can_increment_step
  end

  # Move this DeathRecord one step forward in its Workflow.
  def increment_step
    if self.step_status.current_step == self.step_flow.current_step
      # We are incrementing withing the context of the normal workflow.
      self.step_flow = self.step_flow.next if can_increment_step
      self.step_status.mirror_step_flow(step_flow)
    else
      # We are in the middle of a workflow jump; instead of incrementing
      # to the next StepFlow, we need to reset the state of the StepStatus
      # to where the DeathRecord was before the workflow jump. We also need
      # to restore ownership to the User who requested the change.
      self.step_status.mirror_step_flow(step_flow)
      unless self.step_status.requestor.nil?
        self.owner = self.step_status.requestor # Set owner back to requestor
        self.step_status.requestor = nil # Blank out requestor
      end
    end
    self.step_status.save
    update_cache
    self.save
  end

  # Determines if this DeathRecord can derement its current Step.
  def can_decrement_step
    !step_flow.previous_step.nil?
  end

  # Returns the previous Step in this DeathRecords workflow.
  def previous_step
    self.step_flow.previous_step if can_decrement_step
  end

  # Move this DeathRecord one step backward in its Workflow.
  def decrement_step
    self.step_flow = self.step_flow.prev if can_decrement_step
    self.step_status.mirror_step_flow(self.step_flow)
    self.step_status.save
    update_cache
    self.save
  end

  # Move this DeathRecord to an arbitrary Step in its Workflow by modifying
  # its StepStatus. If linear is true, the DeathRecord's StepStatus will
  # mirror the StepFlow that contains the given step (meaning the
  # will progress normally). If linear is false, only the current_step of
  # the StepStatus is changed, meaning the next time increment_step is called,
  # the DeathRecord will return back to where it was previously. The latter
  # case is particularly useful when, for example, a physician requests edits
  # from a funeral director, and wants the record to return to them after
  # the funeral director makes the requested edits.
  def update_step(step, linear)
    if linear
      self.step_flow = step_flows.find_by(current_step: step)
      self.step_status.mirror_step_flow(self.step_flow)
      self.save
    else
      self.step_status.current_step = step
    end
    self.step_status.save
    update_cache
    self.save
  end

  # Sets the DeathRecord to the given step, and sets the owner to the user
  # who edited or should have edited that step.
  def reassign(step, user)
    # Determine the proper user who should be making the edits
    step_flow = step_flows.find_by(current_step: step)
    target_role = step_flow.current_step_role
    
    # Update the record
    current_step_role
  end

  # Change ownership of this DeathRecord.
  def update_owner(user)
    self.owner = user unless user.nil?
    self.notify = true
    update_cache
    self.save
  end

  # Returns an array of Steps that are editable by the given user for this
  # DeathRecord.
  def steps_editable(user)
    # TODO: Improve efficiency! Way too many DB calls!
    self.workflow.step_flows.where(current_step_role: user.roles.first.name).collect(&:current_step)
  end

  # Check if the given user can edit the given step in the context of this
  # DeathRecord.
  def step_editable?(user, step)
    # TODO: Improve efficiency! Way too many DB calls!
    steps_editable(user).collect(&:name).include? step.name
  end

  # Get the Step that matches the given name, within the context of
  # this DeathRecords Workflow (and is editable by the current owner).
  def editable_step_by_name(user, step_name)
    steps_editable(user).detect{ |step| step.name == step_name }
  end

  # Returns a hash of some simple metadata describing the decedent.
  def metadata
    identity_step = steps.detect{ |step| step.name == 'Identity'}
    if identity_step.step_content(self) && identity_step.step_content(self).key?('decedentName')
      decedentName = identity_step.step_content(self)['decedentName']
    end
    if identity_step.step_content(self) && identity_step.step_content(self).key?('ssn')
      ssn = identity_step.step_content(self)['ssn']
    end
    {
      firstName: decedentName.nil? ? '' : decedentName['firstName'],
      middleName: decedentName.nil? ? '' : decedentName['middleName'],
      lastName: decedentName.nil? ? '' : decedentName['lastName'],
      suffix: decedentName.nil? ? '' : decedentName['suffix'],
      ssn1: ssn.nil? ? '' : ssn['ssn1'],
      ssn2: ssn.nil? ? '' : ssn['ssn2'],
      ssn3: ssn.nil? ? '' : ssn['ssn3']
    }
  end

  # Keep a cached version of the death record JSON for faster loading.
  def update_cache
    self.cached_json = self.generate_json({user: self.owner}) if self.workflow
  end

  def as_json(options = {})
    self.cached_json
  end

  def generate_json(options = {})
    options.merge!({death_record: self})
    # Only load the things we will need.
    next_step_flow = self.workflow.step_flows.includes(:current_step).find_by(current_step: self.step_status.current_step)
    next_step_role = next_step_flow.send_to_role
    next_step_role_pretty = next_step_role.titleize if next_step_role
    steps = []
    self.workflow.steps.each do |step|
      steps.push(step.as_json(options))
    end
    {
      id: self.id,
      owner: self.owner.as_json(options),
      creator: self.creator.as_json(options),
      comments: self.comments.as_json(options),
      stepStatus: self.step_status.as_json(options),
      nextStepRole: next_step_role,
      nextStepRolePretty: next_step_role_pretty,
      steps: steps,
      metadata: metadata,
      lastUpdatedAt: self.updated_at,
      registration: self.registration.as_json(options),
      notify: self.notify
    }
  end

  # Grabs the keys for the given step's jsonSchema
  def get_params_for_step(step)
    if step['jsonschema'].present? && step['jsonschema']['properties'].present?
      return step['jsonschema']['properties'].keys
    end
    return []
  end

  # Generate printable versions of a death certificate for this record and store locally
  def generate_certificate(user)
    # TODO: Eventually we'll want to support multiple, versioned cerficicates
    raise "Death certificate already exists" if self.death_certificate
    # TODO: Placeholder for local certificate generation service
    # document = RestClient.get('http://localhost:4567/certificate', params: self.metadata).body
    pdf = Prawn::Document.new
    # TODO: For now we just create a notional PDF with the JSON content, no formatting
    pdf.text JSON.pretty_generate(self.metadata)
    document = pdf.render
    self.create_death_certificate(document: document, metadata: self.metadata, creator: user)
  end

end

# Adds a function to the Hash class.
class Hash
 # Function creates a flat hash structure by using "." in the keys to represent nesting.
 def self.to_dotted_hash(hash, recursive_key = "")
    hash.each_with_object({}) do |(k, v), ret|
      key = recursive_key + k.to_s
      if v.is_a? Hash
        ret.merge! to_dotted_hash(v, key + ".")
      else
        ret[key] = v
      end
    end
  end

  # Function creates a nested hash from a flat hash with "." notation.
  def self.to_nested_hash(hash)
    hash.each_with_object({}) do |(key, value), all|
      key_parts = key.split('.').map!(&:to_s)
      leaf = key_parts[0...-1].inject(all) { |h, k| h[k] ||= {} }
      leaf[key_parts.last] = value
    end
  end
end
