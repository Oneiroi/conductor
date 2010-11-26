#
# Copyright (C) 2009 Red Hat, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA  02110-1301, USA.  A copy of the GNU General Public License is
# also available at http://www.gnu.org/copyleft/gpl.html.

# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ImageExistsError < Exception;end

class Image < ActiveRecord::Base
  include SearchFilter

  before_save :generate_uuid

  cattr_reader :per_page
  @@per_page = 15

  belongs_to :template, :counter_cache => true
  has_many :replicated_images, :dependent => :destroy
  has_many :providers, :through => :replicated_images

  validates_presence_of :name
  validates_length_of :name, :maximum => 1024
  validates_presence_of :status
  validates_presence_of :target
  validates_presence_of :template_id

  SEARCHABLE_COLUMNS = %w(name)

  STATE_QUEUED = 'queued'
  STATE_CREATED = 'created'
  STATE_BUILDING = 'building'
  STATE_COMPLETE = 'complete'
  STATE_CANCELED = 'canceled'
  STATE_FAILED = 'failed'

  ACTIVE_STATES = [ STATE_QUEUED, STATE_CREATED, STATE_BUILDING ]
  INACTIVE_STATES = [STATE_COMPLETE, STATE_FAILED, STATE_CANCELED]

  def self.available_targets
    return YAML.load_file("#{RAILS_ROOT}/config/image_descriptor_targets.yml")
  end

  def generate_uuid
    self.uuid ||= "image-#{self.template_id}-#{Time.now.to_f.to_s}"
  end

  def self.build(template, target)
    # FIXME: This will need to be enhanced to handle multiple
    # providers of same type, only one is supported right now
    if Image.find_by_template_id_and_target(template.id, target)
      raise ImageExistsError,  "An attempted build of this template for the target '#{target}' already exists"
    end

    unless provider = Provider.find_by_target_with_account(target)
      raise "There is no provider for '#{target}' type with valid account."
    end

    img = nil
    Image.transaction do
      img = Image.create!(
        :name => "#{template.name}/#{target}",
        :target => target,
        :template_id => template.id,
        :status => Image::STATE_QUEUED
      )
      ReplicatedImage.create!(
        :image_id => img.id,
        :provider_id => provider
      )
    end
    return img
  end
end
