# frozen_string_literal: true

require_relative "duel_helper"

# Bluepill runs ps once a tick, and parses the whole listing into the table
# that every watch reads (Bluepill::System.ps_axu). The application's run
# loop clears the last tick's table first, as each iteration does here.
[
  ["ps: parse a container's 10 processes", 10],
  ["ps: parse a server's 300 processes", 300],
  ["ps: parse a large host's 3,000 processes", 3_000]
].each do |name, processes|
  duel name, setup: -> { @listing = ps_listing(processes, workers: 4) }, before_sample: -> { PsListing.output = @listing } do
    Bluepill::System.reset_data
    Bluepill::System.ps_axu
  end
end

# The running_time check reads a process's elapsed time from ps
duel("elapsed: minutes and seconds") { Bluepill::System.parse_elapsed_time("12:41") }
duel("elapsed: days, hours, minutes and seconds") { Bluepill::System.parse_elapsed_time("45-02:13:07") }
