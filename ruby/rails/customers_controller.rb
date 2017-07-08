class CustomersController < ApplicationController


  protect_from_forgery
  load_and_authorize_resource except: [:new, :create, :my_jobs]
  before_filter         :authorize_user_edits,  only: [:edit, :update]
  skip_before_filter :verify_authenticity_token, only: [:my_jobs, :my_jobs_custom]

  #http://localhost:3000/customer/new

  # GET /customer/new
  def new
    @customer = Customer.new
    @customer.user = User.new
  end


  # POST /customer
  def create
    @customer = Customer.new(customer_params)
    if @customer.save
      sign_in @customer.user, bypass: true
      redirect_to root_path
    else
      render 'new'
    end
  end



  # GET /customers/1/edit
  def edit
    load_redirected_objects!
  end


  # PATCH/PUT /customers/1
  def update
   if @customer.user.update(user_params)
      flash[:notice] = "Your profile was updated successfully."
      redirect_to account_customer_path
    else
      set_redirect_object!('@customer', @customer, customer_params)
      redirect_to edit_customer_path(@customer)
    end
  end


  # GET /customer/account
  def account
    @customer = CustomerPresenter.new(current_user.customer, view_context)
  end


  def order_work
  end


  def my_jobs
    @customer = CustomerPresenter.new(current_user.customer, view_context)
    @message_success_pay = params[:message_paid]
    @works = @customer.ordered_work_active
    respond_to do |format|
      format.html
      format.js
    end
  end

  def my_jobs_custom
    @customer = CustomerPresenter.new(current_user.customer, view_context)
    @message_success_pay = params[:message_paid]

    # @works = @customer.ordered_work_active

    if (params[:status]) == 'active'
      @works = @customer.ordered_work_active
    else
      @works = @customer.ordered_work_finished
    end

    sort_by_field = params[:sorted_by]
    @works = sort_works(sort_by_field, @works)

    render(partial: 'lists', locals: { works: @works })
  end

  def sort_works(param, works)
    if param.include? 'asc'
      param.slice! "asc"
      works.sort! { |a, b|  a.send(param) <=> b.send(param) }
    else
      param.slice! "desc"
      works.sort! { |a, b|  b.send(param) <=> a.send(param)}
    end
  end

  def my_jobs_status
    @customer = CustomerPresenter.new(current_user.customer, view_context)
    if (params[:status]) == 'active'
      @works = @customer.ordered_work_active
    else
      @works = @customer.ordered_work_finished
    end

    render(partial: 'lists', locals: { works: @works })
  end


  ###################################################################
  # PRIVATE METHODS
  private


  def authorize_user_edits
    @user = @customer.user
    authorize! :update, @user
  end


  ###################################################################
  # STRONG PARAMS


  # Never trust parameters from the scary internet
  def customer_params
#   params.require(:contact_information).permit(:id, :user_id, :phone_number, :street_address, :street_address_2, :city, :state, :zip)
#   params.require(:person).permit(:name, :age, pets_attributes: [ :name, :category ])
    params.require(:customer).permit(:id, user_attributes: [ :first_name, :last_name, :email, :password, :password_confirmation,
                                                             :street_address, :city, :state, :zip, :phone_number,
                                                             :opt_in_email, :opt_in_sms, :referral_source ])
  end


  def user_params
    params.require(:user).permit(:first_name, :last_name, :email, :password, :password_confirmation,
                                 :street_address, :city, :state, :zip, :phone_number,
                                 :opt_in_email, :opt_in_sms, :avatar, :referral_source)
  end


end
