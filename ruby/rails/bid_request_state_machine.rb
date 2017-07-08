module BidRequest::BidRequestStateMachine
  extend ActiveSupport::Concern

  included do

    state_machine :state, :initial => :drafted do

      state :drafted,                 value: 0
      state :created,                 value: 1
      state :accepted,                value: 2
      state :worked,                  value: 3
      state :approved,                value: 5

      state :payment_errored,         value: -1
      state :cancelled,               value: -2
      state :arbitrated_completed,    value: -4
      state :arbitrated_incompleted,  value: -5


      # List Bid Request for bidding
      event :list do
        transition :drafted => :created
      end

      # A bid is accepted by the customer
      event :accept do
        transition :created => :accepted
      end

      # Bid request is unaccepted by admin
      event :unaccept do
        transition :accepted => :created
      end

      # Work is completed
      event :work do
        transition :accepted => :worked
      end

      # Customer approves completed work
      event :approve do
        transition :worked => :approved
      end

      # System approves a job automatically
      event :automated_approve do
        transition :worked => :approved
      end

      # Customer cancels a bid request
      event :cancel do
        transition [:created, :accepted, :worked] => :cancelled
      end

      # Admin arbitrates a job and credits the contractor with a completion
      event :arbitrate_complete do
        transition [:accepted, :worked] => :arbitrated_completed
      end

      # Admin arbitrates a job and docks the contractor an incompletion
      event :arbitrate_incomplete do
        transition [:accepted, :worked] => :arbitrated_incompleted
      end


      ##################################################
      # Transition Callbacks


      # Customer lists a bid request -------------------------------------------
      after_transition on: :list do |bid_request, transition|
        bid_request.do_list_callback
      end


      # Customer accepts a bid -------------------------------------------------
      before_transition on: :accept do |bid_request, transition|
        # Require a bid be passed on transition
        arguments = transition.require :bid
        bid = arguments[:bid]

        puts "$$$$$"
        pp arguments

        # Verify bid is for this bid request (exception checking)
        unless bid.bid_request_id == bid_request.id
          raise "Attempted to accept bid #{bid.id} " +
          "which does not belong to bid request #{bid_request.id}"
        end

        # Set BidRequest contractor and total
        bid_request.contractor = bid.contractor
        bid_request.total_cost = bid.amount
        bid_request.contractor_payment_amount = bid_request.get_contractor_payment_amount
      end


      after_transition on: :accept do |bid_request, transition|
        bid_request.do_accept_callback
        bid_request.update(accepted_at: Time.new)
      end


      # Admin unaccepts a bid request
      before_transition on: :unaccept do |bid_request, transition|

        # refund
        unless bid_request.customer_payments_paypal.refunded.count > 0
          if bid_request.refund_customer_payment(all: false)
            bid_request.payment_refunded

            if bid_request.order_id
              total_cost = bid_request.originating_order.total_cost
              contractor_payment_amount = bid_request.originating_order.contractor_payment_amount
            else
              total_cost = contractor_payment_amount = nil
            end

            bid_request.update(
            total_cost: total_cost,
            contractor_payment_amount: contractor_payment_amount,
            contractor: nil)
            true
          else
            # There was an error processing refund... alert admin
            bid_request.refund_errored
            false
          end
        end
      end


      # Contractor completes work on the bid request ---------------------------
      after_transition on: :work do |bid_request, transition|
        bid_request.update(reported_at: Time.new)
        bid_request.do_work_callback
      end


      # Customer approves work on the bid request ------------------------------
      after_transition on: :approve do |bid_request, transition|
        bid_request.do_approve_callback
        bid_request.update(approved_at: Time.new)
      end


      # System automatically approves work ------------------------------------
      after_transition on: :automated_approve do |bid_request, transition|
        bid_request.do_automated_approve_callback
      end


      # Customer cancels the bid request ---------------------------------------
      before_transition on: :cancel do |bid_request, transition|
        # Set cancellation fee if appropriate
        # bid_request.add_cancellation_fee if bid_request.in_cancellation_window?
        transition.args.first[:cancel_reason].present?
      end

      after_transition on: :cancel do |bid_request, transition|
        cancel_reason = transition.args.first.present? ? transition.args.first[:cancel_reason] : nil
        bid_request.update(:cancel_reason => cancel_reason) if cancel_reason
        bid_request.do_cancel_callback
      end


      # Arbitration happens ----------------------------------------------------
      after_transition on: :arbitrate_incomplete do |bid_request, transition|
        bid_request.do_arbitrate_callbacks
      end
      after_transition on: :arbitrate_complete do |bid_request, transition|
        bid_request.do_arbitrate_callbacks
      end


    end # state_machine


    # Automate scope generation for all states
    state_machines[:state].states.map do |state|
      scope state.name, -> { where(:state => state.value.to_i) }
    end



  end #included

  ######################################################################
  #   CLASS METHODS

  #def self.customer_payable_model_name
  #  self.class.payable_name
  #end

  module ClassMethods
    def payable_name
      name
    end

    # Builds array of state names
    #
    # @return   Array   states in proper format
    def states
      states = Array.new
      state_machines[:state].states.each do |sm|
        states.push(sm.name)
      end
      states
    end



    # Builds array of states or active_admin in the format [[state, value]]
    #
    # @return   Array     states in proper format
    def state_collection
      states = Array.new
      state_machines[:state].states.each do |sm|
        states.push([sm.name.to_s.titleize, sm.value])
      end
      states
    end

end




end #module
