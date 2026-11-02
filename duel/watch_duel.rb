# frozen_string_literal: true

require_relative "duel_helper"

# What each check does every interval: read the process from the tick's ps
# table, judge the value, add it to the check's history, and log the
# history
hooks = watch_hooks(:mem_usage, below: 1.gigabyte, times: [3, 5], include_children: true)
duel("watch: memory of a process and its 4 workers", **hooks) { run_watch }
duel("watch: CPU of a process, 3 of 5 checks", **watch_hooks(:cpu_usage, below: 50, times: [3, 5])) { run_watch }
duel("watch: running time of a process", **watch_hooks(:running_time, below: 1.day)) { run_watch }
duel("watch: a process for a zombie", **watch_hooks(:zombie_process, {})) { run_watch }
