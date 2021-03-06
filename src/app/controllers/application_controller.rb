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

# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

require 'viewstate.rb'
require 'util/conductor'

class ApplicationController < ActionController::Base
  # FIXME: not sure what we're doing aobut service layer w/ deltacloud
  include ApplicationService
  helper_method :current_user, :filter_view?
  before_filter :read_breadcrumbs, :set_locale

  # General error handlers, must be in order from least specific
  # to most specific
  rescue_from Exception, :with => :handle_general_error
  rescue_from PermissionError, :with => :handle_perm_error
  rescue_from ActionError, :with => :handle_action_error
  rescue_from PartialSuccessError, :with => :handle_partial_success_error
  rescue_from ActiveRecord::RecordNotFound, :with => :handle_active_record_not_found_error
  rescue_from Aeolus::Conductor::API::Error, :with => :handle_api_error

  helper_method :check_privilege
  helper_method :paginate_collection

  protected

  # permissions checking

  def handle_perm_error(error)
    handle_error(:error => error, :status => :forbidden,
                 :title => t('application_controller.access_denied'))
  end

  def handle_partial_success_error(error)
    failures_arr = error.failures.collect do |resource, reason|
      if resource.respond_to?(:display_name)
        resource.display_name + ": " + reason
      else
        reason
      end
    end
    @successes = error.successes
    @failures = error.failures
    handle_error(:error => error, :status => :ok,
                 :message => error.message + ": " + failures_arr.join(", "),
                 :title => t('application_controller.some_actions_failed'))
  end

  def handle_action_error(error)
    handle_error(:error => error, :status => :conflict,
                 :title => t('application_controller.action_error'))
  end

  def handle_general_error(error)
    flash[:error] = error.message
    handle_error(:error => error, :status => :internal_server_error,
                 :title => t('application_controller.internal_server_error'))
  end

  def handle_error(hash)
    logger.fatal(hash[:error].to_s) if hash[:error]
    logger.fatal(hash[:error].backtrace.join("\n ")) if hash[:error]
    msg = hash[:message] || hash[:error].message
    title = hash[:title] || t('application_controller.internal_server_error')
    status = hash[:status] || t('application_controller.internal_server_error')
    respond_to do |format|
      format.html { html_error_page(title, msg, status) }
      format.json { render :json => json_error_hash(msg, status) }
      format.xml { render :xml => xml_errors(msg), :status => status }
    end
  end

  def html_error_page(title, msg, status)
    if request.xhr?
      render :partial => 'layouts/popup-error', :status => status,
             :locals => {:title => title, :errmsg => msg}
    else
      flash[:error] = msg
      render :template => 'layouts/error', :layout => 'application',
             :locals => {:title => title, :errmsg => ''}
    end
  end

  def get_nav_items
    if current_user.present?
      @providers = Provider.list_for_user(current_user, Privilege::VIEW)
      @pools = Pool.list_for_user(current_user, Privilege::VIEW)
    end
  end

  def handle_active_record_not_found_error(error)
    redirect_to :controller => params[:controller]
    flash[:notice] = t('application_controller.flash.notice.record_not_exist')
  end

  def handle_api_error(error)
    render :template => 'api/error', :locals => {:error => error}, :status => error.status
  end

  # Returns an array of ids from params[:id], params[:ids].
  def ids_list(other_attrs=[])
    other_attrs.each do |attr_key|
      return params[attr_key].to_a if params.include?(attr_key)
    end
    if params[:id].present?
      return Array(params[:id])
    elsif params[:ids].present?
      return Array(params[:ids])
    end
  end

  # let's suppose that 'pretty' view is default
  def filter_view?
    if params[:view].present?
      params[:view] == 'filter'
    elsif params[:details_tab].present?
      true
    elsif @viewstate
      @viewstate.state['view'] == 'filter'
    end
  end

  private
  def json_error_hash(msg, status)
    json = {}
    json[:success] = (status == :ok)
    json.merge!(instance_errors)
    # There's a potential issue here: if we add :errors for an object
    # that the view won't generate inline error messages for, the user
    # won't get any indication what the error is. But if we set :alert
    # unconditionally, the user will get validation errors twice: once
    # inline in the form, and once in the flash
    json[:alert] = msg unless json[:errors]
    return json
  end

  def xml_errors(msg)
    xml = {}
    xml[:message] = msg
    xml.merge!(instance_errors)
    return xml
  end

  def instance_errors
    hash = {}
    arr = Array.new
    instance_variables.each do |ivar|
      val = instance_variable_get(ivar)
      if val && val.respond_to?(:errors) && val.errors.size > 0
        hash[:object] = ivar[1, ivar.size]
        hash[:errors] ||= []
        val.errors.each {|key,msg|
          arr.push([key, msg.to_a].to_a)
        }
        hash[:errors] += arr
      end
    end
    return hash
  end

  def http_auth_user
    return unless request.authorization && request.authorization =~ /^Basic (.*)/m
    authenticate!(:scope => :api)
    # we use :api scope for authentication to avoid saving session.
    # But it's handy to set authenticated user in default scope, so we
    # can use current_user, instead of current_user(:api)
    env['warden'].set_user(user(:api)) if user(:api)
    return user(:api)
  end

  def require_user
    return if current_user or http_auth_user
    respond_to do |format|
      format.html do
        store_location
        flash[:notice] = t('application_controller.flash.notice.must_be_logged')
        redirect_to login_url
      end
      format.js { head :unauthorized }
      format.xml { head :unauthorized }
      format.json { head :unauthorized }
    end
  end

  def require_user_api
    return if current_user or http_auth_user
    respond_to do |format|
      format.xml { head :unauthorized }
    end
  end

  def require_no_user
    return true unless current_user
    store_location
    flash[:notice] = t('application_controller.flash.notice.must_not_be_logged')
    redirect_to account_url
  end

  def store_location
    session[:return_to] = request.fullpath
  end

  def redirect_back_or_default(default)
    redirect_to(default || session[:return_to])
    session[:return_to] = nil
  end

  ############################################################################
  # Breadcrumb-Related functionality
  ############################################################################

  def read_breadcrumbs
    session[:breadcrumbs] ||= []
    @read_breadcrumbs = session[:breadcrumbs].last(2)
  end

  def clear_breadcrumbs
    return if request.format == :json

    session[:breadcrumbs] = []
  end

  def save_breadcrumb(path, name = controller_name)
    return if request.format == :json

    session[:breadcrumbs] ||= []
    breadcrumbs = session[:breadcrumbs]
    viewstate = @viewstate ? @viewstate.id : nil

    #if item with desired path is already in bc, then remove every bc behind it
    if index = breadcrumbs.find_index {|b| b[:path] == path || path.split('?')[0] == b[:path] }
      breadcrumbs.slice!(index, breadcrumbs.length)
    end
    read_breadcrumbs
    name = t("breadcrumbs.#{name}") if self.controller_name.eql?(name)
    breadcrumbs.push({:name => name, :path => path, :viewstate => viewstate, :class => self.controller_name})

    session[:breadcrumbs] = breadcrumbs
  end

  def set_admin_content_tabs(tab)
    @tabs = [{:name => t('application_controller.admin_tabs.catalogs'), :url => catalogs_url, :id => 'catalogs'},
             {:name => t('application_controller.admin_tabs.realms'), :url => realms_url, :id => 'realms'},
             {:name => t('application_controller.admin_tabs.hardware'), :url => hardware_profiles_url, :id => 'hardware_profiles'},
    ]
    unless @details_tab = @tabs.find {|t| t[:id] == tab}
      raise "Tab '#{tab}' doesn't exist"
    end
  end

  def set_admin_users_tabs(tab)
    @tabs = [{:name => t('application_controller.admin_tabs.users'), :url => users_url, :id => 'users'},
             #{:name => t('application_controller.admin_tabs.groups'), :url => groups_url, :id => 'groups'},
             {:name => t('application_controller.admin_tabs.permissions'), :url => permissions_url, :id => 'permissions'},
    ]
    unless @details_tab = @tabs.find {|t| t[:id] == tab}
      raise "Tab '#{tab}' doesn't exist"
    end
  end

  def set_admin_environments_tabs(tab)
    @tabs = [{:name => t('application_controller.admin_tabs.pool_families'), :url => pool_families_url, :id => 'pool_families'},
             {:name => t('application_controller.admin_tabs.images'), :url => images_url, :id => 'images'},
    ]
    unless @details_tab = @tabs.find {|t| t[:id] == tab}
      raise "Tab '#{tab}' doesn't exist"
    end
  end

  def sort_column(model, default = nil)
    return params[:order_field] if model.column_names.include?(params[:order_field])
    return default || "#{model.quoted_table_name}.name"
  end

  def sort_direction
    %w[asc desc].include?(params[:order_dir]) ? params[:order_dir] : "asc"
  end

  def add_permissions_inline(perm_obj, path_prefix = '', polymorphic_path_extras = {})
    @permission_object = perm_obj
    @path_prefix = path_prefix
    @polymorphic_path_extras = polymorphic_path_extras
    @roles = Role.find_all_by_scope(@permission_object.class.name)
    set_permissions_header
  end

  def add_permissions_tab(perm_obj, path_prefix = '', polymorphic_path_extras = {})
    @path_prefix = path_prefix
    @polymorphic_path_extras = polymorphic_path_extras
    if "permissions" == params[:details_tab]
      require_privilege(Privilege::PERM_VIEW, perm_obj)
      @permission_object = perm_obj
    end
    if perm_obj.has_privilege(current_user, Privilege::PERM_VIEW)
      @roles = Role.find_all_by_scope(@permission_object.class.name)
      if @tabs
        @tabs << {:name => t('role_assignments'),
                  :view => 'permissions',
                  :id => 'permissions',
                  :count => perm_obj.permissions.count,
                  :pretty_view_toggle => 'disabled'}
      end
    end
    set_permissions_header
  end

  def set_permissions_header
    @permission_list_header = [
      { :name => 'checkbox', :class => 'checkbox', :sortable => false },
      { :name => t('users.index.username') },
      { :name => t('users.index.last_name'), :sortable => false },
      { :name => t('users.index.first_name'), :sortable => false },
      { :name => t("role"), :sort_attr => :role},
    ]
  end

  def set_locale
    I18n.locale = env.nil? || env['HTTP_ACCEPT_LANGUAGE'].nil? ? I18n.default_locale : detect_locale
  end

  def detect_locale
    # Processes the HTTP_ACCEPT_LANGUAGE header
    languages = env['HTTP_ACCEPT_LANGUAGE'].split(',')
    prefs = []
    languages.each do |language|
      language += ";q=1.0" unless language.match(";q=\d+\.\d+")
      lang_code, lang_weight = language.split(";q=")
      lang_code = lang_code.gsub(/-[a-z]+$/i) { |x| x.upcase }.to_sym
      prefs << [lang_weight, lang_code]
    end

    # Orders the requested languages only by weight
    ordered_languages = prefs.sort_by{ |weight, code| weight }.reverse.collect{|p| p[1]}.uniq

    # Returns the lang_code if a requested language is a substring of an available language or vice-versa
    ordered_languages.each do |ordered_lang_code|
      I18n.available_locales.each do |available_lang_code|
        return available_lang_code if available_lang_code.to_s[ordered_lang_code.to_s] || ordered_lang_code.to_s[available_lang_code.to_s]
      end
    end

    # Returns the default_locale otherwise
    I18n.default_locale
  end

  def redirect_to_original(extended_params = {})
    path = params[:current_path]
    # In cases when current_path contains prefix like '/conductor' recognize_path fails.
    # It needs to be stripped out in order to get the path correctly.
    root = ENV['RAILS_RELATIVE_URL_ROOT']
    path = path.slice(root.length..path.length) if path.starts_with? root
    path = Rails.application.routes.recognize_path(path)
    original_params = Rack::Utils.parse_nested_query(URI.parse(params[:current_path]).query)
    redirect_to path.merge(original_params).merge(extended_params)
  end

  def paginate_collection(collection, page = nil, per_page = PER_PAGE)
    result = collection.paginate(:page => page, :per_page => per_page)
    result = collection.paginate(:page => result.total_pages, :per_page => per_page) if result.out_of_bounds? && result.total_pages > 0

    result
  end

end
