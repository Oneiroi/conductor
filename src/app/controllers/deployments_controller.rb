#
#   Copyright 2011 Red Hat, Inc.
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

class DeploymentsController < ApplicationController
  before_filter :require_user
  before_filter :load_deployments, :only => [:index, :show]
  before_filter :load_deployment, :only => [:edit, :update]
  before_filter :check_inaccessible_instances, :only => :multi_stop


  viewstate :show do |default|
    default.merge!({
      :view => 'pretty',
    })
  end

  def index
    save_breadcrumb(deployments_path(:viewstate => viewstate_id))
    respond_to do |format|
      format.html
      format.js { render :partial => 'list' }
      format.json { render :json => @deployments }
    end
  end

  # It is expected that params[:pool_id] will be set on requests into this method
  def launch_new
    @title = t 'deployments.new_deployment'
    @pool = Pool.find(params[:pool_id]) or raise "Invalid pool"
    require_privilege(Privilege::CREATE, Deployment, @pool)
    unless @pool.enabled
      flash[:warning] = t 'deployments.flash.warning.disabled_pool'
      redirect_to pool_path(@pool) and return
    end

    @deployment = Deployment.new(:pool_id => @pool.id)
    init_new_deployment_attrs
    respond_to do |format|
      format.html
      format.js { render :partial => 'launch_new' }
      format.json { render :json => @deployment }
    end
  end



  def launch_time_params
    @title = t 'deployments.new_deployment'
    unless params.has_key?(:deployable_id)
      flash[:error] = t('deployments.flash.warning.deployable_not_selected')
      redirect_to launch_new_deployments_path(:pool_id => params[:deployment][:pool_id]) and return
    end

    @deployment = Deployment.new(params[:deployment])
    @pool = @deployment.pool
    init_new_deployment_attrs
    require_privilege(Privilege::CREATE, Deployment, @pool)
    require_privilege(Privilege::USE, @deployable)
    img, img2, missing, d_errors = @deployable.get_image_details
    flash[:error] = d_errors unless d_errors.empty?

    unless @deployable && @deployable.xml && @deployment.valid_deployable_xml?(@deployable.xml) && d_errors.empty?
      render 'launch_new' and return
    end

    load_assemblies_services

    if @services.empty? or @services.all? {|s, a| s.parameters.empty?}
      # we can skip the launch-time parameters screen
      @errors = @deployment.check_assemblies_matches(current_user)
      set_errors_flash(@errors)
      @additional_quota = count_additional_quota(@deployment)
      render 'overview' and return
    end
  end

  def overview
    @title = t 'deployments.new_deployment'
    @deployment = Deployment.new(params[:deployment])
    @pool = @deployment.pool
    init_new_deployment_attrs
    require_privilege(Privilege::CREATE, Deployment, @pool)
    require_privilege(Privilege::USE, @deployable)
    @launch_parameters_encoded = Base64.encode64(ActiveSupport::JSON.encode(@deployment.launch_parameters))
    img, img2, missing, d_errors = @deployable.get_image_details
    flash[:error] = d_errors unless d_errors.empty?

    respond_to do |format|
      if @deployable.xml && @deployment.valid_deployable_xml?(@deployable.xml) && d_errors.empty?
        @errors = @deployment.check_assemblies_matches(current_user)
        set_errors_flash(@errors)
        @additional_quota = count_additional_quota(@deployment)

        format.html
        format.js { render :partial => 'overview' }
        format.json { render :json => @deployment }
      else
        format.html { render :launch_new }
        format.js { render :partial => 'launch_new' }
        format.json { render :json => @deployment.errors, :status => :unprocessable_entity }
      end
    end
  end

  def create
    launch_parameters_encoded = params.delete(:launch_parameters_encoded)
    unless launch_parameters_encoded.blank?
      decoded_parameters = JSON.load(Base64.decode64(launch_parameters_encoded))
      params[:deployment][:launch_parameters] = decoded_parameters
    end
    @deployment = Deployment.new(params[:deployment])
    @pool = @deployment.pool
    require_privilege(Privilege::CREATE, Deployment, @pool)
    init_new_deployment_attrs
    @deployment.deployable_xml = @deployable.xml if @deployable && @deployable.xml
    if params.has_key?(:deployable_id)
      require_privilege(Privilege::USE, @deployable)
    end
    img, img2, missing, d_errors = @deployable.get_image_details
    respond_to do |format|
      unless d_errors.empty?
        @pool = @deployment.pool
        flash.now[:warning] = t "deployments.flash.warning.failed_to_launch"
        flash[:error] = d_errors
        format.html { render :action => 'overview' }
        format.js { launch_new }
        format.json { render :json => d_errors, :status => :unprocessable_entity }
      else

        @deployment.owner = current_user
        load_assemblies_services
        if params.delete(:commit) == 'back'
          view = launch_parameters_encoded.blank? ? 'launch_new' : 'launch_time_params'
          render view and return
        end

        if @deployment.save
          status = @deployment.launch(current_user)
          if status[:errors].empty?
            flash[:notice] = t "deployments.flash.notice.launched"
          else
            flash[:error] = {
              :summary  => t("deployments.flash.error.failed_to_launch_assemblies"),
              :failures => status[:errors],
              :successes => status[:successes]
            }
          end
          format.html { redirect_to deployment_path(@deployment) }
          format.js do
            @deployment_properties = @deployment.properties
            render :partial => 'properties'
          end
          format.json { render :json => @deployment, :status => :created }
        else
          # We need @pool to re-display the form
          @pool = @deployment.pool
          flash.now[:warning] = t "deployments.flash.warning.failed_to_launch"
          init_new_deployment_attrs
          format.html { render :action => 'overview' }
          format.js { launch_new }
          format.json { render :json => @deployment.errors, :status => :unprocessable_entity }
        end
      end
    end
  end

  def show
    @deployment = Deployment.find(params[:id])
    @title = t('deployments.show.name', :name => @deployment.name)
    require_privilege(Privilege::VIEW, @deployment)
    init_new_deployment_attrs
    save_breadcrumb(deployment_path(@deployment, :viewstate => viewstate_id), @deployment.name)
    @failed_instances = @deployment.failed_instances
    if filter_view?
      @view = 'instances/list'
      params[:instances_preset_filter] = "" unless params[:instances_preset_filter]
      @instances = paginate_collection(Instance.apply_filters(:preset_filter_id => params[:instances_preset_filter], :search_filter => params[:instances_search]).
                                                list(sort_column(Instance), sort_direction).where("instances.deployment_id" => @deployment.id),
                                       params[:page], PER_PAGE)
    else
      @view = 'pretty_view_show'
      @instances = paginate_collection(Instance.list(sort_column(Instance), sort_direction).where("instances.deployment_id" => @deployment.id),
                                       params[:page], PER_PAGE)
    end
    #TODO add links to real data for history, permissions, services
    @tabs = [{:name => t('instances.instances.other'), :view => @view, :id => 'instances', :count => @deployment.instances.count, :pretty_view_toggle => 'enabled'},
             #{:name => 'Services', :view => @view, :id => 'services'},
             #{:name => 'History', :view => 'history', :id => 'history'},
             {:name => t('properties'), :view => 'properties', :id => 'properties', :pretty_view_toggle => 'disabled'}
    #{:name => 'Permissions', :view => 'permissions', :id => 'permissions'}
    ]
    add_permissions_tab(@deployment)
    details_tab_name = params[:details_tab].blank? ? 'instances' : params[:details_tab]
    @details_tab = @tabs.find {|t| t[:id] == details_tab_name} || @tabs.first[:name].downcase
    @deployment_properties = @deployment.properties
    if params[:details_tab]
      @view = @details_tab[:view]
    end
    respond_to do |format|
      format.html { render :action => 'show'}
      format.js   { render :partial => @details_tab[:view] }
      format.json { render :json => @deployment }
    end
  end

  def edit
    require_privilege(Privilege::MODIFY, @deployment)
    respond_to do |format|
      format.html
      format.js { render :partial => 'edit' }
      format.json { render :json => @deployment }
    end
  end

  # TODO - This should eventually support updating multiple objects
  def update
    attrs = {}
    params[:deployment].each_pair{|k,v| attrs[k] = v if Deployment::USER_MUTABLE_ATTRS.include?(k)}
    respond_to do |format|
      if check_privilege(Privilege::MODIFY, @deployment) and @deployment.update_attributes(attrs)
        flash[:success] = t('deployments.flash.success.updated', :count => 1, :list => @deployment.name)
        format.html { redirect_to @deployment }
        format.js do
          @deployment_properties = @deployment.properties
          render :partial => 'properties'
        end
        format.json { render :json => @deployment }
      else
        flash[:error] = t('deployments.flash.error.not_updated', :count => 1, :list => @deployment.name)
        format.html { render :action => :edit }
        format.js { render :partial => 'edit' }
        format.json { render :json => @deployment.errors, :status => :unprocessable_entity }
      end
    end
  end

  def destroy
    deployment = Deployment.find(params[:id])
    if check_privilege(Privilege::MODIFY, deployment)
      begin
        deployment.stop_instances_and_destroy!
        flash[:success] = t('deployments.flash.success.deleted', :list => deployment.name, :count => 1)
      rescue
        flash[:error] = t('deployments.flash.error.not_deleted', :list => deployment.name, :count => 1)
      end
    else
      flash[:error] = t('deployments.flash.error.not_deleted', :list => deployment.name, :count => 1)
    end
    respond_to do |format|
      format.js do
        load_deployments
        render :partial => 'list'
      end
      format.html { redirect_to pools_url(:view => 'filter', :details_tab => 'deployments') }
      format.json { render :json => {:success => destroyed, :errors => failed} }
    end
  end

  def multi_destroy
    destroyed = []
    failed = []

    Deployment.find(params[:deployments_selected] || []).each do |deployment|
      if check_privilege(Privilege::MODIFY, deployment)
        begin
          deployment.stop_instances_and_destroy!
          destroyed << deployment.name
        rescue
          failed << deployment.name
        end
      else
        failed << deployment.name
      end
    end
    # If nothing is selected, display an error message:
    flash[:error] = t('deployments.flash.error.none_selected') if failed.blank? && destroyed.blank?
    flash[:success] = t('deployments.flash.success.deleted', :list => destroyed.to_sentence, :count => destroyed.size) if destroyed.present?
    flash[:error] = t('deployments.flash.error.not_deleted', :list => failed.to_sentence, :count => failed.size) if failed.present?
    respond_to do |format|
      format.html { redirect_to params[:backlink] || pools_url(:view => 'filter', :details_tab => 'deployments') }
      format.js do
        load_deployments
        render :partial => 'list'
      end
      format.json { render :json => {:success => destroyed, :errors => failed} }
    end
  end

  def multi_stop
    notices = []
    errors = []

    @deployments_to_stop.each do |deployment|
      deployment.instances.each do |instance|
        log_prefix = "#{t('deployments.deployment')}: #{instance.deployment.name}, #{t('instances.instance')}:  #{instance.name}"
        begin
          require_privilege(Privilege::USE, instance)
          if @inaccessible_instances.include?(instance)
            instance.forced_stop(current_user)
            notices << "#{log_prefix}: #{t('instances.flash.notice.forced_stop')}"
          else
            instance.stop(current_user)
            notices << "#{log_prefix}: #{t('instances.flash.notice.stop')}"
          end
        rescue Exception => err
          errors << "#{log_prefix}: #{err}"
          logger.error err.message
          logger.error err.backtrace.join("\n ")
        end
      end
    end
    # If nothing is selected, display an error message:
    errors = t('deployments.flash.error.none_selected') if notices.blank? and errors.blank?
    flash[:notice] = notices unless notices.blank?
    flash[:error] = errors unless errors.blank?
    respond_to do |format|
      format.html { redirect_to pools_path(:details_tab => 'deployments', :filter_view => filter_view?) }
      format.js do
        load_deployments
        render :partial => 'list'
      end
      format.json { render :json => {:success => notices, :errors => errors} }
    end
  end

  # Quick method to check if a deployment name is taken or not
  # TODO - The AJAX calls here have a potential race condition; might want to include params[:name]
  # in the output to help catch this and discard output if appropriate
  def check_name
    render :text => params[:name].empty? ? false : Deployment.find_by_name(params[:name]).nil?
  end

  def launch_from_catalog
    @catalog = Catalog.find(params[:catalog_id])
    @deployables = @catalog.deployables.list_for_user(current_user, Privilege::VIEW).paginate(:page => params[:page] || 1, :per_page => 6)
    require_privilege(Privilege::VIEW, @catalog)
  end

  def filter
    redirect_to_original({"deployments_preset_filter" => params[:deployments_preset_filter], "deployments_search" => params[:deployments_search]})
  end

  private

  def check_inaccessible_instances
    @deployments_to_stop = Deployment.find(params[:deployments_selected] || [])
    @inaccessible_instances = Deployment.stoppable_inaccessible_instances(@deployments_to_stop)
    if params[:terminate].blank? and @inaccessible_instances.any?
      respond_to do |format|
        format.html { render :action => :confirm_terminate }
        format.json { render :json => {:inaccessbile_instances => @inaccessible_instances}, :status => :unprocessable_entity }
      end
      return false
    end
    return true
  end

  def load_deployments
    @deployments_header = [
      { :name => 'checkbox', :class => 'checkbox', :sortable => false },
      { :name => '', :class => 'alert', :sortable => false },
      { :name => t("deployments.deployment_name"), :sortable => false },
      { :name => t("pools.index.deployed_on"), :sortable => false },
      { :name => t("deployables.index.base_deployable"), :sortable => false },
      { :name => t("deployables.index.state"), :sortable => false },
      { :name => t("instances.instances.other"), :class => 'center', :sortable => false },
      { :name => t("pools.pool"), :sortable => false },
      { :name => t("pools.index.owner"), :sortable => false },
      { :name => t("providers.provider"), :sortable => false }
    ]
    @pools = Pool.list_for_user(current_user, Privilege::CREATE, Deployment)
    @deployments = paginate_collection(Deployment.includes(:owner, :pool, :instances).
                                                  apply_filters(:preset_filter_id => params[:deployments_preset_filter], :search_filter => params[:deployments_search]).
                                                  list_for_user(current_user, Privilege::VIEW).
                                                  where('deployments.pool_id' => @pools).
                                                  order(sort_column(Deployment, "deployments.name") +' '+ sort_direction),
                                       params[:page], PER_PAGE)
  end

  def count_additional_quota(deployment)
    assembly_count = deployment.deployable_xml.assemblies.count
    @additional_quota = deployment.pool.quota.percentage_used(assembly_count)
  end

  def load_deployment
    @deployment = Deployment.find(params[:id])
    @pool = @deployment.pool
  end

  def set_errors_flash(errors)
    unless errors.empty?
      flash.now[:error] = {
          :failures => errors
      }
    end
  end

  def init_new_deployment_attrs
    @deployables = Deployable.includes({:catalogs => :pool}).list_for_user(current_user, Privilege::USE).select{|d| d.catalogs.collect{|c| c.pool}.include?(@pool)}
    @pools = Pool.list_for_user(current_user, Privilege::CREATE, Deployment)
    @deployable = params[:deployable_id] ? Deployable.find(params[:deployable_id]) : nil
    @realms = FrontendRealm.all
    @hardware_profiles = HardwareProfile.all(
        :include => :architecture,
        :conditions => {:provider_id => nil}
    )
    @realm_choices = @realms.map{|r| [r.name, r.id]}
    @realm_choices.unshift([I18n.t('deployments.launch_new.autoselect'), ''])
  end

  def load_assemblies_services
    @services = []
    @deployment.deployable_xml.assemblies.each do |assembly|
      assembly.services.each do |service|
        @services << [service, assembly.name]
      end
    end
  end

end
