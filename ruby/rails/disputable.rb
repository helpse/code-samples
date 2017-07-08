# This module does not work unless the extending model also includes Commentable
#
module Disputable
  extend ActiveSupport::Concern


  ######################################################################
  #   CLASS IMPLEMENTATIONS
  included do

    # Associations
    has_many      :disputes,              as: :disputable,        dependent: :restrict_with_error

  end


  ######################################################################
  #   PUBLIC METHODS

  # Get the current dispute
  #
  # @return   Dispute             Current dispute (nil if none)
  #
  def current_dispute
    disputes.order(created_at: :desc).first
  end

  # Check if this work has an open dispute or not
  #
  # @return   Boolean             If this model has an open dispute
  #
  def disputed?
    disputes.opened.present?
  end


  # Find duration of current dispute if any
  #
  # @return   Float               Epoch duration of current dispute, duration
  #                               of most recent closed dispute, or nil if
  #                               there is no current dispute.
  #
  def dispute_duration
    most_recent_dispute = disputes.last
    return nil if most_recent_dispute.blank?

    started_at  = most_recent_dispute.created_at
    ended_at    = most_recent_dispute.resolved_at

    most_recent_dispute.opened? ? (Time.new - created_at) : (resolved_at - created_at)
  end



  # When this order was last disputed
  #
  # @return   Time                Time of most recent dispute on this order
  #
  def disputed_at
    disputes.opened.maximum(:created_at)
  end



  # Checks if a user is the initiator for the dispute on this job
  #
  # @param    User    user        The user to check
  # @return   Boolean             If the user disputed this order
  #
  def disputed_by?(user)
    most_recent_dispute = disputes.last
    (most_recent_dispute.present? && most_recent_dispute.user.id == user.id) ? true : false
  end



  # Checks if there is a current dispute and if so if it is in arbitration
  #
  # @return   Boolean               If this dispute is in arbitration
  #
  def in_arbitration?
    return false unless disputed?
    current_dispute.deadline_at <= Time.now
  end


  # Resolve a dispute on this work
  #
  # Resolves a dispute on this work object.  This involves:
  # - Adding the user's comment to the work
  # - Adding a system comment stating the dispute is closed
  #
  # @param  User    disputer        The person disputing the work
  # @param  Hash    dispute_params  Params to use for the user comment
  # @return Boolean                 If the dispute was ended successfully
  #
  def resolve_dispute(disputer, dispute_params)
    success = false

    unless disputed_by? disputer
      raise "A dispute can only be resolved by the user that created it"
    end

    # Wrap comments in transaction so if one fails they both rollback
    self.transaction do
      unless comment(disputer, dispute_params)
        puts "~~~ Error saving user dispute comment"
        raise ActiveRecord::Rollback
      end

      dispute_comment = add_dispute_resolution_comment
      unless dispute_comment
        puts "~~~ Error saving system dispute comment"
        raise ActiveRecord::Rollback
      end

      unless resolve_dispute_record(disputer, dispute_comment)
        puts "~~~ Error creating dispute object"
        raise ActiveRecord::Rollback
      end

      CustomerOrderMailer.order_dispute_resolved(self).deliver
      ContractorOrderMailer.order_dispute_resolved(self).deliver
      AdminOrderMailer.order_dispute_resolved(self).deliver

      success = true
    end

    # Return sucess flag
    success
  end



  # Start a dispute on this work
  #
  # Starts a dispute on this work object.  This involves:
  # - Adding the user's comment to the work
  # - Adding a system comment stating the work is in dispute
  #
  # @param  User    disputer        The person disputing the work
  # @param  Hash    dispute_params  Params to use for the user comment
  # @return Boolean                 If the dispute was begun successfully
  #
  def start_dispute(disputer, dispute_params)
    success = false

    # Wrap comments in transaction so if one fails they both rollback
    self.transaction do
      unless comment(disputer, dispute_params)
        puts "~~~ Error saving user dispute comment"
        raise ActiveRecord::Rollback
      end

      dispute_comment = add_dispute_comment
      unless dispute_comment
        puts "~~~ Error saving system dispute comment"
        raise ActiveRecord::Rollback
      end

      unless add_dispute_record(disputer, dispute_comment)
        puts "~~~ Error creating dispute object"
        raise ActiveRecord::Rollback
      end

      CustomerOrderMailer.order_disputed(self).deliver
      ContractorOrderMailer.order_disputed(self).deliver
      AdminOrderMailer.order_disputed(self).deliver

      success = true
    end

    # Return sucess flag
    success
  end


  ######################################################################
  #   PRIVATE METHODS
  private


  # Enters a comment at the start of a dispute for this job
  #
  # @return   Comment           The dispute comment (or nil if save fails)
  #
  def add_dispute_comment
    params = {  user_id:        User.system_user.id,
                body:           'This job has entered dispute.',
                comment_type:   :dispute
            }

    comment = comments.build(params)

    # Return nil if save fails, the comment otherwise
    comment.save ? comment : nil
  end



  # Enters a comment at the end of a dispute for this job
  #
  # @return   Comment           The dispute comment (or nil if save fails)
  #
  def add_dispute_resolution_comment
    params = {  user_id:        User.system_user.id,
                body:           'The dispute on this job has been resolved',
                comment_type:   :dispute
              }
    comment = comments.build(params)
    comment.save ? comment : nil
  end



  # Create a dispute comment for this work
  #
  # @param  Comment   dispute_comment     The initiating comment for dispute
  # @return Boolean                       If the record is created successfully
  #
  def add_dispute_record(user, dispute_comment)
    dispute = disputes.build
    dispute.initiating_comment_id = dispute_comment.id
    dispute.user_id = user.id
    dispute.save ? dispute : nil
  end



  # Create a dispute resolution comment for this work
  #
  # @param  Comment   resolution_comment  The initiating comment for dispute
  # @return Boolean                       If the record is created successfully
  #
  def resolve_dispute_record(user, resolution_comment)
    dispute = disputes.opened.first
    dispute.resolving_comment_id = resolution_comment.id
    dispute.resolve ? dispute : nil
  end




end #module
