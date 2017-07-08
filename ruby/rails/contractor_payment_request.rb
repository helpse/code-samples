class ContractorPaymentRequest < ActiveRecord::Base
  include TransitionCallbacks, Liquidatable, StatePermissible, ContractorDeposit

  # Associations
  has_many      :orders,                    dependent: :restrict_with_error
  has_many      :bid_requests,              dependent: :restrict_with_error
  belongs_to    :contractor
  belongs_to    :contractor_payment_batch

  # Attributes
  attr_reader   :processor

  # Callbacks
  after_initialize  :set_default_item_id
  after_find        :update_payment_status,      unless: :terminal_payment_state?

  # Money-rails
  monetize      :amount_cents

  # Liquid Interface
  liquidate_to  :contractor_payment_request_liquid_drop

  # Delegate
  delegate :fullname, :type_account, to: :contractor, prefix: true

  # Scopes
  scope         :funds_requested,       -> { where.not(state: 4) }  # => State Machine != paid
  scope         :funds_withdrawn,       -> { where(state: 4) }      # => State Machine = paid
  scope         :funds_approved,        -> { where(state: 2) }      # => State Machine = approved
  scope         :batchable,             -> { funds_approved.where("contractor_payment_batch_id IS NULL OR contractor_payment_batch_id NOT IN (?)", ContractorPaymentBatch.select(:id).uniq) }
  scope         :paypal_complete,       -> { where("upper(payment_status) in (?)", ContractorBatchPayoutProcessor::ITEM_TERMINAL_STATES) }
  scope         :paypal_in_progress,    -> { where.not("upper(payment_status) in (?)", ContractorBatchPayoutProcessor::ITEM_TERMINAL_STATES) }


  # Validations


  # State-Permissions
  permit        :approve,               only: [:requested, :payment_erred]


  ######################################################################
  #   STATE_MACHINE DEFINITION AND HELPER FUNCTIONS


  state_machine :state, :initial => :requested do

    state :requested,       value: 1
    state :approved,        value: 2
    state :pending,         value: 3
    state :paid,            value: 4
    state :payment_erred,   value: -1


    # Request approved
    event :approve do
      transition [:requested, :payment_erred] => :approved
    end

    # Request unapproved
    event :unapprove do
      transition :approved => :requested
    end

    # Request attempted
    event :initiate do
      transition [:requested, :approved, :pending, :payment_erred] => :pending
    end

    # Request paid
    event :pay do
      transition [:pending] => :paid
    end

    # Payment Errored
    event :payment_err do
      transition [:approved, :pending] => :payment_erred
    end


    # --- Callbacks ---------
    after_transition to: :approved do |cpr|
      cpr.update(
        approved_at: Time.new,
        paid_at: nil,
        contractor_payment_batch_id: nil
      )
    end

    after_transition to: :requested do |cpr|
      cpr.update(approved_at: nil)
    end

    after_transition to: :paid do |cpr|
      cpr.update(paid_at: Time.new)
      cpr.do_pay_callback
    end

  end # state_machine

  # Automate scope generation for all states
  state_machines[:state].states.map do |state|
    scope state.name, -> { where(:state => state.value.to_i) }
  end

# Builds array of state names
    #
    # @return   Array   states in proper format
    def self.states
      states = Array.new
      state_machines[:state].states.each do |sm|
        states.push(sm.name)
      end
      states
    end



    # Builds array of states or active_admin in the format [[state, value]]
    #
    # @return   Array     states in proper format
    def self.state_collection
      states = Array.new
      state_machines[:state].states.each do |sm|
        states.push([sm.name.to_s.titleize, sm.value])
      end
      states
    end

  ######################################################################
  #   PUBLIC CLASS METHODS


  def self.rolling_earnings
    # Calculate Sums By Contractor
    datetime_cutoff = Time.now - Settings.contractor_payment_request.rolling_earning_recency
    earnings_by_contractor = ContractorPaymentRequest.where("created_at > ?", datetime_cutoff).group(:contractor_id).sum(:amount_cents)

    # Convert cents to dollars
    Hash[earnings_by_contractor.map {|k, v| [k, v/100]}]

  end

  def self.total_amount_cents
    pluck(:amount_cents).reduce(:+)
  end




  ######################################################################
  #   PUBLIC METHODS


  # Add jobs (and validate states/contractor id) to this payment request
  #
  # @param  Array     job_hashes      Array of hashes of jobs in the format
  #                                   "JobType:JobID" where JobType is a job
  #                                   type such as Order or Bid Request.
  # @return Boolean                   If the record was saved successfully
  #
  def add_and_verify_jobs(job_hashes)

    # Prepare array to hold jobs
    jobs = Array.new

    # Validate state of jobs and contractor status
    job_hashes.uniq.each do |job_hash|
      (job_type, job_id) = fetch_job(job_hash)
      job = job_type.find(job_id)

      unless job.contractor_payable? && contractor.id == job.contractor.id
        # This job is not in a state to be paid... bail out of function
        # returning false
        return false
      end

      jobs << job
    end

    success = nil

    # Create associations and save total to this model
    self.transaction do
      self.amount = 0

      jobs.each do |job|
        # Running total of amoutn
        puts "job amount: #{self.amount}"
        case job.class.name
        when "Order"
          self.amount = Money.new(self.amount) + Money.new(job.contractor_payment_amount)
          orders << job
        when "JobBidRequest", "MowingBidRequest"
          self.amount = Money.new(self.amount) + Money.new(job.contractor_payment_amount)
          bid_requests << job
        end
      end

      # Attempt save
      success = save
    end

    # Return if save was successful
    success
  end


  # Poll PayPal for the status on this item
  #
  # Updating is gated to once every 1m.  This should prevent infinite
  # recursion with individual request updates.
  #
  def update_payment_status

    # We don't need to update if the last update was within 1m
    return nil if payment_status_updated_at.present? && payment_status_updated_at > Time.now - 1.minutes
    update(payment_status_updated_at: Time.new)

    if contractor_payment_batch.present? && contractor_payment_batch.paid?
      @processor = ContractorBatchPayoutProcessor.new(contractor_payment_batch)
      @processor.update_item_status(self)
    end
  end

  ######################################################################
  #   PRIVATE METHODS
  private


  # Break a Job hash up into a model type and id
  #
  def fetch_job(hash)
    (job_type, job_id) = hash.split(/:/)
    return [job_type.constantize, job_id]
  end



  # Generate a unique itemid to use for this record
  #
  def generate_item_id
    loop do
      iid = "CPR" + SecureRandom.hex(10)
      break iid unless ContractorPaymentRequest.where(sender_item_id: iid).first
    end
  end



  # Create an item ID for this record if one does not exist yet
  #
  def set_default_item_id
    self.sender_item_id ||= generate_item_id
  end



  # Checks if this item is in a terminal paypal state
  #
  # Terminal paypal states are states that once the paypal payout reaches it,
  # paypal will not provide us with a new status.  It's reached the end of the
  # line, and we can stop re-checking for updates.
  #
  # A nil paypal state also does not need to be processed, thus is terminal
  #
  # @return   Boolean           If this batch is in a terminal state
  #
  def terminal_payment_state?
    payment_status.present? && ContractorBatchPayoutProcessor::ITEM_TERMINAL_STATES.include?(payment_status)
  end


end
