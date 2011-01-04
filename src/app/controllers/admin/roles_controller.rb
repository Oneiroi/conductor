class Admin::RolesController < ApplicationController
  before_filter :require_user
  before_filter :load_roles, :only => [:index, :show]

  def create
    @role = Role.new(params[:role])

    # TODO: (lmartinc) Fix this and let user select the scope. Consult with sseago.
    @role.scope = BasePermissionObject.to_s if @role.scope.nil?

    if @role.save
      flash[:notice] = 'Role successfully saved!'
      redirect_to admin_roles_path and return
    end

    render :action => 'new'
  end

  def show
    @role = Role.find(params[:id])

    @url_params = params.clone
    @tab_captions = ['Properties']
    @details_tab = params[:details_tab].blank? ? 'properties' : params[:details_tab]
    respond_to do |format|
      format.js do
        if @url_params.delete :details_pane
          render :partial => 'layouts/details_pane' and return
        end
        render :partial => @details_tab
      end
      format.html { render :partial => @details_tab }
    end
  end

  def edit
    @role = Role.find(params[:id])
  end

  def update
    @role = Role.find(params[:id])

    if params[:commit] == "Reset"
      redirect_to edit_admin_role_url(@role) and return
    end

    if @role.update_attributes(params[:role])
      flash[:notice] = 'Role updated successfully!'
      redirect_to admin_roles_url and return
    end

    render :action => 'edit'
  end

  def multi_destroy
    Role.destroy(params[:role_selected])
    redirect_to admin_roles_url
  end

  protected

  def load_roles
    @header = [
      { :name => "Role name", :sort_attr => :name }
    ]
    @roles = Role.paginate(:all,
      :page => params[:page] || 1,
      :order => (params[:order_field] || 'name') +' '+ (params[:order_dir] || 'asc')
    )
    @url_params = params.clone
  end

end
