#
#   Copyright 2012 Red Hat, Inc.
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

class ProviderRealmsController < ApplicationController
  before_filter :require_user
  before_filter :load_realms, :only =>[:index, :show]

  def index
    clear_breadcrumbs
    save_breadcrumb(provider_realms_path)
    set_admin_content_tabs 'realms'
    respond_to do |format|
      format.html
      format.js { render :partial => 'list' }
    end
  end

  def show
    @realm = Realm.find(params[:id])
    @title = @realm.name

    @tab_captions = [t('realms.tab_captions.properties'), t('realms.tab_captions.mapping')]
    @details_tab = params[:details_tab].blank? ? 'properties' : params[:details_tab]

    @frontend_realms_for_provider = @realm.provider.frontend_realms
    @frontend_realms = @realm.frontend_realms
    @provider_accounts = @realm.provider_accounts

    save_breadcrumb(provider_realm_path(@realm), @realm.name)

    respond_to do |format|
      format.html { render :action => 'show' }
      format.js do
        if params.delete :details_pane
          render :partial => 'layouts/details_pane' and return
        end
        render :partial => @details_tab
      end
      format.json { render :json => @realm }
    end
  end

  def filter
    redirect_to_original({"provider_realms_preset_filter" => params[:provider_realms_preset_filter], "provider_realms_search" => params[:provider_realms_search]})
  end

  protected

  def load_realms
    @header = [
      {:name => '', :sortable => false},
      {:name => t("provider_realms.name"), :sort_attr => :name},
    ]
    @realms = Realm.apply_filters(:preset_filter_id => params[:provider_realms_preset_filter], :search_filter => params[:provider_realms_search])
  end
end
