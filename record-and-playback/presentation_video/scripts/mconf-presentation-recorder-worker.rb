#!/usr/bin/ruby
# Set encoding to utf-8
# encoding: UTF-8

#
# BigBlueButton open source conferencing system - http://www.bigbluebutton.org/
#
# Copyright (c) 2012 BigBlueButton Inc. and by respective authors (see below).
#
# This program is free software; you can redistribute it and/or modify it under the
# terms of the GNU Lesser General Public License as published by the Free Software
# Foundation; either version 3.0 of the License, or (at your option) any later
# version.
#
# BigBlueButton is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License along
# with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.
#

Dir.chdir(File.expand_path(File.dirname(__FILE__)))

require '../lib/recordandplayback'
require 'rubygems'
require 'yaml'
require 'fileutils'
require 'pathname'

BigBlueButton.logger = Logger.new("/var/log/bigbluebutton/mconf-presentation-video-worker.log",'daily' )

$props = YAML::load(File.open('mconf-presentation-recorder.yml'))
$bbb_props = YAML::load(File.open('bigbluebutton.yml'))

def parent_dir(file)
  Pathname(file).each_filename.to_a[-2]
end

def metadata_to_record_id(metadata)
  parent_dir(metadata)
end

def is_display_free(display_id)
  command = "xdpyinfo -display :#{display_id}"
  begin
    BigBlueButton.execute(command)
  rescue
    return true
  end
  return false
end

def get_free_display
  while true
    candidate = rand(65536)
    return candidate if is_display_free(candidate)
  end
end

# This worker is instantiated only once by God.
# record_meeting has an infinite loop that looks for new meetings to record
def record_meeting
  published_dir = $bbb_props['published_dir']
  unpublished_dir = $bbb_props['unpublished_dir']
  presentation_recorder_dir = $props['presentation_recorder_dir']

  # record_in_progress = {}
  record_in_progress = Hash[(Dir.entries("/var/bigbluebutton/recording/process/presentation_recorder") - ['.', '..']).map {|v| [v, nil]}]

  while true
    published_meetings = Hash[Dir.glob("#{published_dir}/presentation/**/metadata.xml").map {|v| [metadata_to_record_id(v), v]}]
    unpublished_meetings = Hash[Dir.glob("#{unpublished_dir}/presentation/**/metadata.xml").map {|v| [metadata_to_record_id(v), v]}]
    all_meetings = published_meetings.merge(unpublished_meetings)
    recorded_meetings = Dir.glob("/var/bigbluebutton/recording/status/processed/**/*-presentation_recorder.done").map {|v| File.basename(v).sub(/-presentation_recorder.done/, '')}
    recorded_meetings.each do |k|
      BigBlueButton.wait record_in_progress[k] if not record_in_progress[k].nil?
      record_in_progress.delete k
    end
    meetings_to_record = all_meetings.keys - recorded_meetings - record_in_progress.keys
    meetings_to_record.sort! {|x,y| x.sub(/.*-/, "") <=> y.sub(/.*-/, "")}

    BigBlueButton.logger.info "Published meetings:\n#{BigBlueButton.hash_to_str(published_meetings)}"
    BigBlueButton.logger.info "Unpublished meetings:\n#{BigBlueButton.hash_to_str(unpublished_meetings)}"
    BigBlueButton.logger.info "All meetings (published + unpublished):\n#{BigBlueButton.hash_to_str(all_meetings)}"
    BigBlueButton.logger.info "Meetings already recorded:\n#{BigBlueButton.hash_to_str(recorded_meetings)}"
    BigBlueButton.logger.info "Meetings being recorder right now:\n#{BigBlueButton.hash_to_str(record_in_progress)}"
    BigBlueButton.logger.info "Meetings to record:\n#{BigBlueButton.hash_to_str(meetings_to_record)}"

    if not meetings_to_record.empty?
      meetings_to_record.each do |record_id|
        if record_in_progress.count >= 2
          break
        end

        # send to presentation_recorder the metadata xml
        command = "ruby record/presentation_recorder.rb -m #{all_meetings[record_id]} -d #{get_free_display}"
        record_in_progress[record_id] = BigBlueButton.execute_async(command)
      end
    end

    sleep 30
  end
end

record_meeting

BigBlueButton.logger.info("Worker terminated")