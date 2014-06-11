#require 'background_process' #https://github.com/timcharper/background_process https://rubygems.org/gems/background_process
require 'yaml'
require 'thread'
require 'trollop'

require '../../core/lib/recordandplayback'

module BigBlueButton

	# All necessary bash commands to output a video
	class VideoRecorder

#		include Singleton

		# Load yaml file with recording properties
		$props = YAML::load(File.open('presentation_video.yml'))
		$bbb_props = YAML::load(File.open('bigbluebutton.yml'))

		def initialize
			@virtual_displays = [*$props['display_first_id']..$props['display_last_id']]
			@display_mutex = Mutex.new
		end

		attr_accessor :target_dir

		# Xvfb PID
		attr_accessor :xvfb

		# Initializes the virtual display using Xvfb
		#
		#   display_id - unique ID of virtual display
		def create_virtual_display(display_id)
			BigBlueButton.logger.info("Task: Starting Xvfb virtual display with ID #{display_id}.")

			command = "Xvfb :#{display_id} -nocursor -screen 0 #{$props['display_setting']}"
			self.xvfb = BigBlueButton.execute_background(command)#BackgroundProcess.run(command)

			# Wait a while until the virtual display is ready
			command = "sleep #{$props['xvfb_wait']}"
			BigBlueButton.execute(command)
		end

		# Firefox PID
		attr_accessor :firefox

		# Fires firefox in virtual display with desired video
		#
		#   display_id - unique ID of virtual display
		#   video_link - link of video to be recorded
		def fire_firefox(display_id, video_link)
			command = "rm -rf #{$props['firefox_home']} && mkdir -p #{$props['firefox_profile']}"
			BigBlueButton.logger.info("Task: Refreshing firefox home and profile folders")
			BigBlueButton.execute(command)

			BigBlueButton.logger.info("Task: Starting firefox in display ID #{display_id}")

			#main_props = "--display #{display_id} -p #{display_id} -new-window #{video_link}"
			main_props = "-profile #{$props['firefox_profile']} -safe-mode --display :#{display_id} -new-window #{video_link}"
			size_props = "-width #{$props['firefox_width']} -height #{$props['firefox_height']}"
			command = "HOME=#{$props['firefox_home']} firefox #{size_props} #{main_props}"
			self.firefox = BigBlueButton.execute_background(command)

			sleep_cmd = "sleep #{$props['firefox_safemode_wait']}"
			BigBlueButton.execute(sleep_cmd)

			command = "export DISPLAY=:#{display_id} && xdotool key Return"
			BigBlueButton.execute(command)

			BigBlueButton.execute(sleep_cmd)

			command = "export DISPLAY=:#{display_id} && xdotool mousemove #{$props['firefox_width'] - 14} 100 && xdotool click 1"
			BigBlueButton.logger.info("Closing firefox upper message")
			BigBlueButton.execute(command)

			command = "sleep 1"
			BigBlueButton.execute(command)			
		end

		# RecordMyDesktop PID
		attr_accessor :rmd

		# Records the desired video and flushes the data to disk
		#
		#   display_id - unique ID of virtual display
		#   millis - time to record movie in millis
		def record_video(display_id, seconds, output_path)
			# Blocking is better to ensure we will wait until the video starts being recorded
			BigBlueButton.logger.info("Task: Playing video in display ID #{display_id} by clicking on play button")
			command = "export DISPLAY=:#{display_id} && xdotool mousemove #{$props['play_button_x_position']} #{$props['play_button_y_position']} && xdotool click 1"
			BigBlueButton.execute(command)

			BigBlueButton.logger.info("Task: Recording video in display ID #{display_id} with #{seconds}s of duration")
			main_props = "--display :#{display_id} --no-cursor --no-sound -o #{output_path}"
			size_props = "--width #{$props['record_window_width']} --height #{$props['record_window_height']}"
			offset_props = "-x #{$props['record_window_x_offset']} -y #{$props['record_window_y_offset']}"
			command = "recordmydesktop #{main_props} #{size_props} #{offset_props}"
			self.rmd = BigBlueButton.execute_background(command)

			BigBlueButton.logger.info("Task: Waiting #{seconds} seconds until the end of the recording")
			command = "sleep #{seconds}"	
			BigBlueButton.execute(command)
			
			BigBlueButton.logger.info("Task: Recording process terminated. Flushing data to disk.")
			self.rmd.kill("TERM")

			BigBlueButton.logger.debug("Task: Waiting RecordMyDesktop to flush data to disk. Still running? #{self.rmd.running?}")
			self.rmd.wait

			BigBlueButton.logger.info("Task: RecordMyDesktop terminated. Data flushed.")
		end

		# Kills all used processes
		def end_processes

			BigBlueButton.logger.info("Task: Stopping firefox")
			self.firefox.kill("TERM")
			self.firefox.wait

			BigBlueButton.logger.info("Task: Stopping Xvfb")
			self.xvfb.kill("TERM")
			self.xvfb.wait

			#command = "kill -s 15 @firefox_pid @rmd_pid @xvfb_pid"
			#BigBlueButton.logger.info("Task: Killing recording processes at display #{display_id}")
			#BigBlueButton.execute(command)
		end


		# This is the easiest way to record a video as .ogv. This function just calls a shell script that must be stored as
		# ./scripts/record.sh
		#
		#   display_id - unique id of virtual display to be used
		#   seconds - seconds of video to be recorded
		#   web_link - link of video to be recorded
		#   output_path - path to where the video file must be outputed
		def record_by_script(display_id, seconds, web_link, output_path)
			command = "/usr/local/bigbluebutton/core/scripts/record/record.sh #{display_id} #{seconds} #{web_link} #{output_path}"
			BigBlueButton.logger.info("Task: Recording on display #{display_id} during #{seconds} seconds")
			BigBlueButton.execute(command)
		end

		# SYNCHRONIZED: This pops a display id from display id list.
		def pop_free_display		
			@display_mutex.synchronize do
				display_id = @virtual_displays.pop
				BigBlueButton.logger.info("Got display ID: #{display_id}.")
				return display_id
			end
		end

		# SYNCHRONIZED: This 'gives back a display' by pushing the used id back to virtual display list 
		#
		#   display_id - id of used display
		def push_free_display(display_id)
			BigBlueButton.logger.info("Pushing used display ID #{display_id} back to display pool.")
			@display_mutex.synchronize do
				@virtual_displays.push(display_id)
			end
		end

		# This retrieves an available display id to be used. If no display is available after 20 seconds,
		# it returns nil
		#
		# @Return
		#   display_id - ID of virtual display
		def get_free_display
			BigBlueButton.logger.info("Trying to get free display ID from display pool.")
			display_id = self.pop_free_display
			sleep_count = 0

			while display_id == nil
				BigBlueButton.logger.info("Waiting for free display ID.")
				sleep(2)
				sleep_count += 1
				display_id = self.pop_free_display

				if sleep_count >= 5
					BigBlueButton.logger.info("No free display after 5 tries. Returning nil.")
					return nil
				end
			end

			return display_id
		end

		# This converts a playback meeting and outputs a out.avi file at bigbluebutton/published/#{meeting_id}
		#
		#   meeting_id - meeting id of video to be converted
		def record(meeting_id)
			BigBlueButton.logger.info("Preparing to record meeting #{meeting_id}.")

			audio_file = "#{$bbb_props['published_dir']}/presentation/#{meeting_id}/audio/audio.ogg"

			web_link = "http://#{$bbb_props['playback_host']}/#{$props['playback_link_prefix']}?meetingId=#{meeting_id}"

			# Getting time in millis from wav file, will be the recording time
			audio_lenght = (BigBlueButton::AudioEvents.determine_length_of_audio_from_file(audio_file)) / 1000

			display_id = self.get_free_display

			recorded_screen_raw_file = "#{target_dir}/recorded_screen_raw.ogv"
			
			BigBlueButton.logger.debug("CREATE VIRTUAL DISPLAY")
			self.create_virtual_display(display_id)

			BigBlueButton.logger.debug("CREATE FIREFOX")
			self.fire_firefox(display_id, web_link)

			BigBlueButton.logger.debug("CREATE RECORDING")
			self.record_video(display_id, audio_lenght, recorded_screen_raw_file)

			BigBlueButton.logger.debug("KILLING REMAINING PROCESSES")
			self.end_processes

			#BigBlueButton.logger.debug("RECORD BY SCRIPT TO TEST DISPLAY VARIABLES")
			# Start the recording process
			#self.record_by_script(display_id, audio_lenght, web_link, recorded_screen_raw_file)

			# Free used virtual display
			self.push_free_display(display_id)

			format = {
				:extension => 'webm',
				:parameters => [
					[ '-c:v', 'libvpx', '-crf', '34', '-b:v', '60M',
					'-threads', '2', '-deadline', 'good', '-cpu-used', '3',
					'-c:a', 'libvorbis', '-b:a', '32K',
					'-f', 'webm' ]
				]
			}

			final_video_file = "#{target_dir}/meeting"
			BigBlueButton::EDL::encode(audio_file, recorded_screen_raw_file, format, final_video_file, 0)
		end

		def myfunc(wr)
			print "#{wr}\n"
			BigBlueButton.logger.info("My func #{wr}")
		end
	end
end

=begin
BigBlueButton.logger = Logger.new('/var/log/bigbluebutton/presentation_video/video-recorder.log', 'daily' )

opts = Trollop::options do
  opt :meeting_id, "Meeting id to archive", :default => '58f4a6b3-cd07-444d-8564-59116cb53974', :type => String
end

meeting_id = opts[:meeting_id]

BigBlueButton.logger.info("Start recording meeting #{meeting_id}")

BigBlueButton::VideoRecorder.new.myfunc(meeting_id)
=end