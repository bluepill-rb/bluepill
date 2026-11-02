# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/2.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Removed

- **Breaking:** support for Ruby 2.0. Bluepill 0.2.1 needs Ruby 2.1 or newer, or JRuby 9.0 or newer. Bluepill 0.2.0 still runs on Ruby 2.0.

## [0.2.0] - 2026-11-02

### Upgrading from 0.1

Most pill files work with 0.2.0 unchanged. Check these before you upgrade:

- **Bluepill needs Ruby 2.0 or newer.** On Ruby 1.9.3 or JRuby 1.7, stay on 0.1.6, which has every fix that doesn't change behavior, or upgrade Ruby first.
- **A setting bluepill doesn't know now fails the config.** 0.1 quietly ignored a misspelled or unsupported setting in a `process` block, such as `start_comand`. Now `bluepill load` stops with the setting's name and the closest one it knows. The config fails before bluepill touches anything, so a running daemon and its processes keep going, and loading the new config is a safe way to find out.
- **Bluepill no longer loads ActiveSupport for you.** `10.seconds`, `2.minutes`, and `100.megabytes` still work, as plain numbers of seconds and bytes. A pill file that uses anything else from ActiveSupport, such as `5.minutes.ago`, `blank?`, or `present?`, needs the `activesupport` gem and a `require "active_support/all"` (or just the parts it uses) at the top.
- **A process with a `uid` gets that user's groups.** It now runs with every group the user belongs to, as after logging in. Without a `gid`, it used to keep root's groups, and now it gets the user's primary group instead. Set `gid` or `supplementary_groups` for a process that needs a group the user isn't in.
- **With `monitor_children`, the children's commands run as the parent's user.** A child's `stop_command` used to run as root. One that needs root has to get it some other way, such as `sudo`.
- **`pre_start_command` has a time limit.** It now runs like the other hooks, so bluepill kills it after `hook_timeout` (30 seconds by default) and starts the process anyway. Raise `hook_timeout` for a setup step that takes longer, such as a migration. A `pre_start_command` that can't run, such as a missing program, is now logged, and no longer stops the start.
- **A process's `state` is a Symbol.** A custom trigger or check that compares `process.state` with a String, such as `"up"`, needs to compare it with a Symbol, such as `:up`. What `bluepill status`, the log and `notify_command` show is unchanged.
- **The daemon only answers the CLI's commands.** A script that talks to the daemon's socket itself can still send `start`, `stop`, `restart`, `unmonitor`, `status`, `version` and `log_file`, but any other line now gets a `NoMethodError` back instead of calling that method on the daemon.
- **A custom trigger's `notify` gets a smaller transition.** It now has `from_name`, `to_name`, and `loopback?`, which is all bluepill's own triggers use. The `from`, `to`, and `event` that state_machine's transitions also had are gone.

To upgrade, install 0.2.0 and run `bluepill load` with the same pill file. It replaces the running 0.1 daemon and keeps monitoring the processes that are already running, without restarting them. Quitting the 0.1 daemon first works too, since `bluepill quit` leaves the processes running in both versions. Since 0.1.5, each app's journals live in `journals/<app>`, and 0.2.0 still reads and clears the ones that 0.1.4 and earlier wrote. If you go back to 0.1.4 or earlier, it won't see the journals that 0.1.5 and 0.2.0 write.

### Added

- Custom checks have a `logger`, which writes to bluepill's log with the app's and the process's names, and the README shows how to write one ([#7](https://github.com/bluepill-rb/bluepill/issues/7)).
- A `log_level` option for `Bluepill.application`, which drops messages less severe than it, such as `log_level: :warning` ([#47](https://github.com/bluepill-rb/bluepill/issues/47)).
- `supplementary_groups` can be set for the whole app, like `uid` and `gid` ([#28](https://github.com/bluepill-rb/bluepill/issues/28)).
- `post_start_command`, `notify_command`, `pre_stop_command`, and `post_stop_command` hooks. A hook that runs longer than `hook_timeout` is killed, with anything it started. `notify_command` gets the app, group, process, old and new state, reason, and pid in environment variables, and an app can set it for all its processes ([#60](https://github.com/bluepill-rb/bluepill/issues/60)).
- Documented the durations and sizes, such as `10.seconds` and `100.megabytes`, that bluepill adds to `Numeric`, and a spec that fails if bluepill changes any other of Ruby's own classes.

### Changed

- **Breaking:** an attribute in a `process` block that bluepill doesn't know, such as a misspelled `start_comand`, now fails when the config loads, naming the attribute and the process and suggesting the closest one. Before, bluepill accepted it and quietly ignored it ([#40](https://github.com/bluepill-rb/bluepill/issues/40)).
- **Breaking:** a process's `state` is now a Symbol, such as `:up`, where it was a String, such as `"up"`. A custom trigger that compares `process.state` with a String needs to compare it with a Symbol instead. `bluepill status`, the log, and `notify_command`'s `BLUEPILL_FROM` and `BLUEPILL_TO` show the states as before, and a tick that leaves a process's state alone no longer makes a new transition and string to do it.
- **Breaking:** `pre_start_command` now runs like the other hooks. Bluepill waits for it for up to `hook_timeout` (30 seconds by default), kills it if it runs longer, and logs it if it fails to run, then starts the process either way. Before, it had no time limit, and one that couldn't run, such as a missing program, stopped the start. A setup step that takes longer needs a bigger `hook_timeout`.
- **Breaking:** a process with a `uid` now runs with every group the user belongs to, as it would after logging in, and with the user's primary group when it sets no `gid`. Before, it got only its `gid` and `supplementary_groups`, and without a `gid` it kept the root group and root's other groups ([#28](https://github.com/bluepill-rb/bluepill/issues/28)).
- **Breaking:** the commands of a process's children with `monitor_children`, such as their `stop_command`, now run as the parent's `uid`, `gid` and `supplementary_groups`. Before, they ran as root ([#28](https://github.com/bluepill-rb/bluepill/issues/28)).
- A check's method that says whether a value is fine is now `check?`. A custom check that defines `check`, as in bluepill 0.1, still works.
- Each tick does much less work. Compared with 0.1.4 on the benchmarks in `duel/`, a tick of a process that's up takes 94% fewer instructions and makes 2 objects instead of 166, finding a process's children among 300 others takes over 99% fewer, checking the memory of a process and its workers 98% fewer, and parsing `ps` about a third fewer.
- A process's logger works out its prefixes once, and writes straight to the log, so a log line takes 1 allocation instead of 10, and each check's run takes about 10% less time.

### Removed

- **Breaking:** support for Ruby 1.9.3 and JRuby 1.7. Bluepill 0.2 needs Ruby 2.0 or newer, or JRuby 9.0 or newer. Bluepill 0.1.6 still runs on both.
- The `state_machine` dependency, whose last release was in 2013. A process's states and events are now a small transition table in `Bluepill::Process`, which moves between the same states, in the same order of callbacks. With all three dependencies gone, bluepill has no runtime dependencies. This isn't a breaking change ([#61](https://github.com/bluepill-rb/bluepill/issues/61)).
- The `activesupport` dependency, which loaded about 300 files into the daemon for six small methods. `10.seconds`, `2.minutes`, `100.megabytes` and the rest of the durations and sizes that configs use now come from bluepill, as plain numbers of seconds and bytes. Bluepill only adds them where they aren't defined already, so a config that loads ActiveSupport keeps its versions, which bluepill still accepts. This isn't a breaking change ([#61](https://github.com/bluepill-rb/bluepill/issues/61)).
- The `blue-daemons` dependency. Bluepill now has its own copy of the few functions it used from it, as `Bluepill::Daemonize`, so an app that also uses the `daemons` gem no longer gets whichever of the two loads first. This isn't a breaking change ([#61](https://github.com/bluepill-rb/bluepill/issues/61)).

### Fixed

- The README's group example gave every process the same pid file, and its `stop_signals` example waited longer than its stop grace time, so bluepill refused to load either config.

## [0.1.6] - 2026-11-02

### Security

- The daemon now runs only the commands that the CLI sends over its socket: `start`, `stop`, `restart`, `unmonitor`, `status`, `version` and `log_file`. Before, it called whatever method a line on the socket named, so anyone who could write to the socket could call any of the daemon's public methods, such as `instance_eval` with code of their own. The socket takes the daemon's umask, so with the usual umask of 022 only the daemon's own user could connect. Any other command now gets a `NoMethodError` back.

## [0.1.5] - 2026-11-01

### Removed

- `ProcessJournal.kill_all_from_all_journals`, which was meant to kill every journaled process when bluepill started or quit, but looked in the wrong directory and never found any ([#59](https://github.com/bluepill-rb/bluepill/issues/59)). Bluepill still kills what a process's journal lists before it starts that process, and `bluepill load` keeps monitoring the processes that are already running instead of restarting them.

### Fixed

- A restart that stops and starts the process, because a check asked for one or from `bluepill restart`, left bluepill watching the old pid. So the process went from `restarting` to `down` and back to `up`, and bluepill logged an error about signaling the old pid. `bluepill restart` now also goes through `restarting`, like a check's restart, instead of leaving the process `up` with its old pid while it restarts.
- `SIGHUP` never reopened bluepill's log, because daemonizing ignored it after bluepill trapped it. So after log rotation, bluepill kept writing to the rotated file. Bluepill now traps `SIGHUP` again once it has daemonized. Reopening syslog on `SIGHUP` also no longer crashes bluepill, which 0.1.4 did in foreground mode, since it loads syslog only when it logs there.
- Stale journal locks, which a daemon that died leaves behind, were never cleared, since bluepill looked for them in the current directory instead of the journal directory, and removed them as if they were files ([#59](https://github.com/bluepill-rb/bluepill/issues/59)). A stale lock made the next write to its journal wait 10 seconds and fail. Bluepill now clears the app's own locks when it starts and quits.
- After a reboot, or once pids wrapped around, bluepill could kill an unrelated process whose pid it had journaled ([#3](https://github.com/bluepill-rb/bluepill/issues/3)). The journal now records when each process started, and bluepill only kills a pid whose process started then. A process group whose leader has exited, and a journal line from bluepill 0.1 and earlier, are only trusted if they were journaled since the machine booted.
- Two apps with a process of the same name shared its journal, so starting the process in one app killed the other app's ([#34](https://github.com/bluepill-rb/bluepill/issues/34)). Each app now keeps its journals in a directory of its own, `journals/<app>`. Journals that bluepill 0.1 and earlier wrote are still read and cleared, so upgrading doesn't leave their processes running.

## [0.1.4] - 2026-11-01

### Added

- `bluepill load` warns about a process that sets none of `daemonize`, `pid_file` or `pid_command`, since bluepill can't find its pid ([#54](https://github.com/bluepill-rb/bluepill/issues/54)).
- Documented `pre_start_command`, and that commands don't run in a shell.
- Gem metadata links to the source code, changelog and issue tracker ([#56](https://github.com/bluepill-rb/bluepill/issues/56)).
- RBS type signatures in `sig/bluepill.rbs`, checked with Steep in strict mode.

### Changed

- Allowed Active Support 6 and newer.
- When cleaning up a process journal, bluepill now sends `KILL` to every process still alive a second after `TERM`, including a single survivor. Before, it only sent `KILL` when more than one process survived, and then to every journaled pid.
- Process groups in the journal are now checked as whole groups, so a group whose leader exited but whose other members are still running gets killed too.
- With `stop_signals`, bluepill now waits for the process to exit, up to about `stop_grace_time`, after the last signal before force-killing it from the journal ([#31](https://github.com/bluepill-rb/bluepill/issues/31)).
- A restart without `restart_command` now waits for the whole `stop_signals` sequence to finish before starting the process again ([#31](https://github.com/bluepill-rb/bluepill/issues/31)).
- `start` now ends a stop sequence that is still running, so it can't signal or kill the newly started process ([#31](https://github.com/bluepill-rb/bluepill/issues/31)).
- `ps` now runs with the POSIX options `-Ao pid,ppid,pcpu,rss,etime,args` ([#13](https://github.com/bluepill-rb/bluepill/issues/13)).
- When `ps` can't run, the daemon logs a warning and skips that check until the next interval instead of exiting ([#37](https://github.com/bluepill-rb/bluepill/issues/37)).
- When bluepill can't open its log file or create its pids directory, it explains which user needs access and exits with status 5 instead of printing a backtrace ([#33](https://github.com/bluepill-rb/bluepill/issues/33)).
- An HTTP check with an unknown numeric `kind` now fails when the pill loads, like an unknown String or Symbol `kind` already did. Before, it raised on every tick and kept the process's other checks from running.

### Removed

- `Bluepill::Application::Client` and `Bluepill::Application::Server`, which raised `TypeError` when loaded and weren't used.
- The `sample_forking_server` executable. It was a test server for the examples, so it moved to `examples/` and is no longer installed with the gem.

### Fixed

- On Ruby 3.4 and newer, loading bluepill under Bundler raised `LoadError` unless the app's Gemfile included `syslog`, even when logging to a file. Bluepill now loads `syslog` only when it logs to syslog, and explains how to fix a missing `syslog` gem.
- The HTTP condition with a numeric `kind`, and `stop_signals` with delays, crashed on Ruby 3.2 and newer, where `Fixnum` no longer exists.
- Two processes could hold the journal lock at the same time, the lock never timed out, and a waiting process could remove a lock held by another.
- A `nil` pid crashed the process journal, and a pid of 0 made bluepill journal its own process group.
- A pid file that was empty or held 0 made the process show as `up` forever, since signaling pid 0 reaches bluepill's own process group ([#53](https://github.com/bluepill-rb/bluepill/issues/53)).
- Checking a process that had no pid yet, such as before its first start, logged a "Failed to signal process" error.
- Commands sent to a process whose name contains a colon raised `ArgumentError` ([#24](https://github.com/bluepill-rb/bluepill/issues/24)).
- `stop` or `restart` on a starting process with `monitor_children` raised `SystemStackError` ([#8](https://github.com/bluepill-rb/bluepill/issues/8)).
- A start, stop or restart command that outlived its grace time left a zombie process behind ([#23](https://github.com/bluepill-rb/bluepill/issues/23)).
- `ps` failed on SmartOS and Solaris ([#13](https://github.com/bluepill-rb/bluepill/issues/13)).
- Starting a second daemon for an app that was already running raised `NameError` instead of printing an error and exiting.
- Event timestamps in `bluepill status` showed the hour where they meant the minutes.
- The `file_time` check crashed when the file couldn't be read.
- The command listener stopped answering after `accept` failed once.
- Several watches could run `ps` at the same time on the same tick.
- Each reset of a trigger left its canceled events in memory.
- A start, stop or restart command killed by a signal could crash the daemon, since the command has no exit code.
- The `running_time` check could crash the daemon when `ps` didn't list the process.
- The HTTP check's workaround for a Net::HTTP connection error never matched on Ruby 3.4 and newer, which changed the error message.
- An empty or garbled application pid file made bluepill send `SIGINT` to its own process group on startup.
- `bluepill quit` with an empty or garbled daemon pid file sent `TERM` to the process group of the `bluepill` command itself.
- Loading a config rejected two different processes as duplicates when joining group and process name with `:` gave the same string, such as process `b:c` in group `a` and process `c` in group `a:b`.
- Child processes of a process that didn't set its grace times got no start, stop or restart grace time, instead of the default of 3 seconds.

## [0.1.3] - 2017-04-06

### Changed

- Allowed `activesupport` 5, so bluepill can be used with Rails 5 ([#46](https://github.com/bluepill-rb/bluepill/pull/46)).
- Documented that bluepill can only run in the foreground on JRuby.

## [0.1.2] - 2016-06-19

### Fixed

- Killed journaled pids and remove the pid file only after a long-running `stop_command` or `stop_signals` sequence has finished, instead of right away ([#32](https://github.com/bluepill-rb/bluepill/pull/32)).
- Fixed cleanup of stale pid and socket files for applications that are no longer running.
- Read command exit codes from `$?` instead of `$CHILD_STATUS`, which is only set when the `English` library is loaded ([#43](https://github.com/bluepill-rb/bluepill/pull/43)).
- Treated an invalid pid (such as `false`) as a process that is not running instead of raising an error.

## [0.1.1] - 2015-08-14

### Changed

- **Breaking:** Required Ruby 1.9.3 or later in the gemspec, so RubyGems no longer installs this release on Ruby 1.8.
- Updated the README and examples to use Ruby 1.9 hash syntax.

## [0.1.0] - 2015-08-14 [YANKED]

### Removed

- **Breaking:** Dropped Ruby 1.8 support. The code now uses Ruby 1.9 hash syntax, but the gemspec did not yet declare a minimum Ruby version.

## [0.0.70] - 2015-08-14

### Changed

- Raised the minimum `activesupport` version to 3.2.
- Relaxed the `blue-daemons` dependency to `~> 1.1`.
- `bluepill status` now lists every process, not just processes that monitor their children.

### Removed

- Removed the unused `i18n` runtime dependency.

### Fixed

- Only write child pids to the process journal for processes that bluepill daemonizes ([#26](https://github.com/bluepill-rb/bluepill/pull/26)).
- Fixed a `NoMethodError` (`undefined method 'actual_id'`) when restarting a process whose children are monitored ([#35](https://github.com/bluepill-rb/bluepill/pull/35)).

## [0.0.69] - 2014-11-02

### Changed

- Logged a backtrace when a trigger or process condition raises an exception ([#18](https://github.com/bluepill-rb/bluepill/pull/18)).

### Fixed

- Required `active_support` before its core extensions to work around a Rails loading bug ([#19](https://github.com/bluepill-rb/bluepill/pull/19)).

## [0.0.68] - 2014-07-20

### Changed

- Allowed `activesupport` 4.1 and later 4.x releases, so bluepill can be used with Rails 4.1 ([#17](https://github.com/bluepill-rb/bluepill/pull/17)).

### Fixed

- The `mem_usage` check no longer raises an error when a process has no memory reading.

## [0.0.67] - 2014-05-01

### Added

- Added a `zombie_process` check that restarts defunct processes. It requires `cache_actual_pid` to be set to `false`.

### Changed

- Allowed `activesupport` 4.0, so bluepill can be used with Rails 4.0.
- Switched to the `blue-daemons` fork instead of the `daemons` gem.

### Fixed

- Reported exceptions raised in the grandchild process of a blocking command instead of losing them silently.
- Prevented the grandchild process from crashing while reporting an exception after its error pipe is closed ([#10](https://github.com/bluepill-rb/bluepill/pull/10)).
- Exited the intermediate daemonizing process with `Process.exit!` so it does not run exit handlers.

## [0.0.66] - 2013-07-19

### Fixed

- Fixed starting the bluepill daemon without privileges, which still failed in 0.0.62 because `Errno::EPERM` was not rescued correctly.

## [0.0.65] - 2013-07-12

### Changed

- Limited `activesupport` to 3.x, since `activesupport` 4 requires Ruby 1.9.3.

### Fixed

- `bluepill restart` now starts a process right after stopping it when no `restart_command` is set, instead of waiting for the next tick.

## [0.0.64] - 2013-05-29

### Added

- Added a `running_time` check that fires when a process has been running longer than a given time.
- Added the `BLUEPILL_BASE_DIR` environment variable to set the default base directory.

### Changed

- **Breaking:** The default base directory for unprivileged users is now `~/.bluepill` instead of `/var/run/bluepill`.
- Loosened the `state_machine` dependency to `~> 1.1`.

### Fixed

- Fixed an error when daemonizing a process fails.
- Fixed the load path of the `local-bluepill` script.
- Exited the child process of a blocking command with `Process.exit!` so it does not leave zombie processes behind.

## [0.0.63] - 2013-04-21

### Added

- Added a `file_time` check that fires when a file, such as a log file, has not been modified recently.
- Added the `group_start_noblock`, `group_stop_noblock`, `group_restart_noblock` and `group_unmonitor_noblock` process options. Set them to `false` to run group commands one process at a time instead of in parallel.
- Added the `on_start_timeout` process option to choose what happens when a start command takes longer than `start_grace_time`.

### Changed

- A process whose start command times out is now started again by default instead of being unmonitored.

### Fixed

- The `http` check now sends the query string along with the path.
- Stopped retrying forever when deleting a file fails.
- Process journals are now stored in the base directory instead of the current working directory.

## [0.0.62] - 2013-03-19

### Fixed

- Fixed a crash when starting the bluepill daemon without privileges.

## [0.0.61] - 2013-03-18

### Added

- Added the `kill_timeout` application option to set how long bluepill waits for a previous bluepill daemon to exit. It defaults to 10.
- Added `pre_start_command`, a command that runs before each start of a process.
- Added the `include_children` option to `cpu_usage` and `mem_usage` checks to count the resources of child processes.
- Kept a journal of the pids and process groups that bluepill starts, and kill leftover processes from it when starting and stopping.

### Changed

- Allowed `daemons` 1.1.7 and later again.
- Documented the application name argument of the `bluepill` command.

### Fixed

- Accepted a `working_dir` that is not a string, such as a `Pathname`.

## [0.0.60] - 2012-03-05

### Fixed

- Fixed sending `stop_signals`, which are given as symbols and broke in 0.0.59.

## [0.0.59] - 2012-02-27

### Fixed

- Fixed sending numeric signals to a process, and log an error when sending a signal fails instead of failing silently.

## [0.0.58] - 2012-02-20

### Removed

- Removed the workaround for `daemons` 1.1.7 and later, which are still excluded by the gemspec.

## [0.0.57] - 2012-02-20

### Fixed

- Only set `close_on_exec` on socket connections when the Ruby version supports it.

## [0.0.56] - 2012-02-18

### Changed

- Restricted the `daemons` dependency to 1.1.6 or earlier again.

### Fixed

- Fixed sending signals on Ruby 1.8.7, where symbols do not respond to `upcase`.

## [0.0.55] - 2012-02-07

### Changed

- Supported `daemons` 1.1.7 and later.

## [0.0.54] - 2012-02-07

### Changed

- Restricted the `daemons` dependency to versions 1.1.4 through 1.1.6.

## [0.0.53] - 2012-02-03

### Fixed

- Set up Bundler when bluepill runs under `bundle exec`, to avoid gem conflicts.
- Closed socket connections when a command execs, so a long-running command no longer makes the client time out.

## [0.0.52] - 2011-12-13

### Added

- Added the `supplementary_groups` process option.
- Added the `stop_signals` process option to send a sequence of signals with delays when stopping a process.
- The client now retries up to 5 times when the server does not respond.

### Changed

- **Breaking:** The default base directory is now `/var/run/bluepill` instead of `/var/bluepill`.
- Set the `HOME` environment variable to the home directory of the configured `uid`.
- Required `state_machine` 1.1 instead of 0.9.

### Fixed

- Fixed a `Config` deprecation warning on Ruby 1.9.3.
- Fixed `bluepill status` not returning output.
- Fixed an error when `supplementary_groups` is not set.

## [0.0.51] - 2011-06-01

### Fixed

- Fixed `bluepill status <process>`, which failed while printing the process's event history since 0.0.47.

## [0.0.50] - 2011-06-01

### Added

- Added the `pid_command` process option to get a process's pid from the output of a command instead of a pid file.
- Added the `auto_start` option. Set it to `false` so that processes which aren't running when bluepill loads start out unmonitored instead of being started.
- Added a simpler DSL: `Bluepill.application` and `app.process` blocks that take no argument are evaluated in the proxy's context, and attributes can be set with `working_dir "/path"` or `daemonize!` instead of `process.working_dir = "/path"`. The block-argument style still works.

## [0.0.49] - 2011-05-14

### Added

- Added the `cache_actual_pid` process option (default `true`). Set it to `false` to reread the pid file on every check.

### Fixed

- Fixed loading the `state_machine` gem on systems that also have the `rubyist-aasm` gem installed.

## [0.0.48] - 2011-04-07

### Changed

- **Breaking:** Bluepill now requires ActiveSupport 3.0 or later and `state_machine` 0.9.4 or later in the 0.9 series.

### Removed

- Removed the dependency on `blankslate`.

### Fixed

- Fixed a crash when a command run by bluepill (such as a stop or restart command) returned no status output.

## [0.0.47] - 2011-04-05

### Changed

- Raised the timeout for commands sent to the bluepill daemon from 10 to 60 seconds, so busy daemons have time to respond.
- **Breaking:** Tightened the gem dependencies to `daemons ~> 1.1.0`, `activesupport ~> 2.3.4`, `blankslate ~> 2.1.2.3` and `i18n ~> 0.5.0`, which rules out ActiveSupport 3.

## [0.0.46] - 2011-03-25

### Added

- Added `i18n` as a dependency, since newer ActiveSupport versions need it but don't declare it.

## [0.0.45] - 2011-03-24

### Added

- Added HTTPS support to the `:http` check. Certificates are not verified.
- Added the ability to turn off restarting after flapping by setting the flapping trigger's `retry_in` to `0`.
- Added a `-t`/`--timeout` option to the `bluepill` command, although it doesn't affect the command timeout yet.

### Fixed

- Fixed a race condition that made the flapping trigger unreliable, and removed its misleading "Retrying from flapping" log message.
- Fixed orphaned processes caused by start commands being run through `sh -c`. Commands are now split into words and executed directly.
- Fixed an `ArgumentError` from the signal handlers on Ruby 1.9.2.
- Fixed triggers on monitored child processes on Ruby 1.9.
- Fixed a race condition when deleting a process's pid file that another process had already removed.
- Fixed process monitoring on FreeBSD by changing the `ps` invocation.

## [0.0.44] - 2010-10-19

### Changed

- `bluepill` now exits with status 1 when given an unknown command.

### Fixed

- Fixed monitoring child processes on Ruby 1.9, which failed because a mutex could not be marshaled.

## [0.0.43] - 2010-09-19

### Fixed

- Restored Ruby 1.8.6 compatibility, which 0.0.39 had broken by using `Object#tap`.
- Fixed monitoring child processes on Ruby 1.9, which lacks `Array#nitems`.

## [0.0.42] - 2010-08-24

### Added

- Environment variable names and values set with `environment` can now be symbols or other non-string objects.

### Fixed

- Fixed loading configuration files on Ruby 1.9.2.
- Fixed the `bluepill` command's help output on Ruby 1.9.

## [0.0.40] - 2010-08-21

### Added

- Added the `--no-privileged` option so `bluepill` can run as a non-root user. Bluepill then skips switching `uid` and `gid` for its processes.

### Fixed

- Fixed a spurious error at startup when the pid file of a previous bluepill daemon pointed to a process that was no longer running.

## [0.0.39] - 2010-08-02

### Added

- Added the `environment` option, at the application or process level, to set environment variables for monitored processes.
- Added the `:http` check, which requests a URL and checks the response status and, optionally, its body against a pattern.

### Fixed

- Fixed compatibility with Rails 3 and ActiveSupport 3.0.

## [0.0.38] - 2010-05-31

### Fixed

- Fixed child processes still not inheriting their parent's grace times after the 0.0.37 change.

## [0.0.37] - 2010-03-15

### Added

- Added the `:foreground => true` option to `Bluepill.application` to run bluepill in the foreground without daemonizing and log to stdout, for use under runit or similar supervisors.

### Fixed

- Fixed child processes not inheriting the parent's grace times when they were set after `monitor_children`.

## [0.0.36] - 2010-02-28

### Fixed

- Fixed an error when closing a client connection that had already been closed.

## [0.0.35] - 2010-02-28

### Fixed

- Fixed a second bluepill daemon starting for an application whose daemon was already running. It now exits with an error.

## [0.0.34] - 2010-02-28

### Fixed

- Fixed an error in the daemon when a client disconnected before its connection was closed.

## [0.0.33] - 2010-02-11

### Added

- Added support for calling `bluepill` through a symlink named after an application, like runit and daemontools.

### Fixed

- Fixed race conditions between commands sent to the daemon and the monitoring loop by handling commands one at a time under a lock.

## [0.0.32] - 2010-01-31

No user-facing changes.

## [0.0.31] - 2010-01-15

### Changed

- Errors raised while the daemon runs a command are now sent back and printed by the client, which exits with status 8.

## [0.0.30] - 2009-12-28

### Added

- Added `Bluepill.define_process_condition` to define a custom process condition from a block.
- Added process statistics, so `bluepill status` with a target shows more detail such as the process's recent event history.

## [0.0.28] - 2009-12-27

### Added

- Added the `bpsv` service control script, which runs `bluepill <command> <name>` using the name it is invoked under (for example through a symlink).

## [0.0.27] - 2009-12-06

### Changed

- `start`, `stop`, `restart` and `unmonitor` no longer require a target and apply to all processes when none is given.
- The CLI now checks that the running daemon is the same bluepill version and aborts with an error if it is out of date.

## [0.0.26] - 2009-12-03

### Changed

- The CLI now prints an error when `start`, `stop`, `restart` or `unmonitor` is run without a target.

## [0.0.25] - 2009-11-30

### Added

- Commands can now target a process by `group:process`, by process name alone, or by group name.
- The CLI now reports which processes were affected by a command.
- The config now fails with an error when two processes share a pid file or when a process name is repeated within a group.

### Changed

- `pid_file` is no longer required for a monitored process and defaults to a file in a per-application subdirectory of the bluepill pids directory.
- `bluepill load` now runs the config file in a fresh Ruby interpreter so that whatever the config loads does not stay in the daemon's memory.
- `bluepill log` now tails the application's configured log file instead of always using the CLI default.
- Redirected `stdout` and `stderr` files are now opened in append mode instead of being truncated.

### Fixed

- Fixed a crash when `bluepill load` was given a file that does not exist.
- Fixed processes in groups whose names were given as symbols not being handled correctly.
- Fixed the `times` option of a condition watch being passed through to the process condition.

## [0.0.24] - 2009-11-24

### Added

- Watch values can now be formatted for display, and the memory usage watch shows values in KB or MB.

### Changed

- Running `bluepill` with no arguments now prints the help.

### Fixed

- An empty pid file is now treated as having no pid.
- Fixed an exception raised when a state transition was halted by a `before_transition` callback.

## [0.0.23] - 2009-11-23

### Added

- Added the `-v`/`--version` option to print the bluepill version.

## [0.0.22] - 2009-11-23

### Added

- Added the `:log_file` application option to log to a file instead of syslog.
- Added the `-h`/`--help` option with usage information.
- Added app-wide `working_dir`, `uid` and `gid` settings that apply to every process that doesn't set its own.
- Added config validation that rejects duplicate process names and child process monitors without a `stop_command`.
- Documented the config options, logging, and working directory in the README and added a license file.

### Changed

- `bluepill` now prints an error and exits when the daemon fails to start instead of only logging the exception.

### Fixed

- The daemon's pid file and socket file are now removed when bluepill quits.

## [0.0.21] - 2009-11-16

### Added

- Added the `stdin`, `stdout` and `stderr` process options to redirect a daemonized process's streams.

### Removed

- **Breaking:** Removed support for shell output redirection in `start_command` because it was racy. Use the new `stdout` and `stderr` options instead.

## [0.0.20] - 2009-11-16

### Changed

- Running `start_command`, `stop_command` and `restart_command` now times out after the matching grace time so a hanging command can't block bluepill.
- Pid files for daemonized processes are now written by the spawned child so they are no longer always owned by the superuser.

### Fixed

- Bluepill now monitors the correct process when a daemonized `start_command` uses output redirection or environment variable assignments.
- Fixed bluepill refusing to start even when run as the superuser.

## [0.0.19] - 2009-11-13

### Changed

- The CLI now exits with distinct non-zero exit codes on errors.
- The base directory now defaults to `/var/bluepill`, and bluepill exits with an error if it can't write to it.
- When loading a config, bluepill now waits for a previous daemon to die and exits with an error if it doesn't.

## [0.0.18] - 2009-11-07

### Changed

- When several applications are running, the CLI now lists the running applications to choose from.

### Fixed

- Fixed the `log` command not picking the application automatically when only one is running.
- `bluepill load` now prints an error instead of crashing when the config file doesn't exist.

## [0.0.17] - 2009-11-07

### Fixed

- Fixed a variable scope error that broke commands sent to the daemon.

## [0.0.16] - 2009-11-07

### Fixed

- Fixed `bluepill load` failing because it was treated as a command for an already running daemon.

## [0.0.15] - 2009-11-06

### Added

- Added a timeout to the CLI's socket connection to the daemon.

### Changed

- Clarified some CLI error messages.

## [0.0.14] - 2009-11-06

### Added

- The CLI now prints an error listing the running applications when an application name is needed, and an error when no bluepill daemons are running.

### Fixed

- Stale socket files from daemons that are no longer running are now cleaned up.

## [0.0.13] - 2009-11-06

### Fixed

- Set the `PWD` environment variable when changing to a process's `working_dir`, to match shell behavior with symlinks.

## [0.0.12] - 2009-11-05

### Added

- Added the `working_dir` process option to set the directory a process starts in.

## [0.0.11] - 2009-11-04

### Changed

- Depended on the `state_machine` gem instead of `pluginaweek-state_machine` and added the missing `blankslate` dependency.
- Replaced the README with a basic usage guide and moved the bug list to GitHub issues.

## [0.0.10] - 2009-10-27

### Fixed

- The log message for `restart_command` now shows the command after `{{PID}}` substitution.

## [0.0.9] - 2009-10-27

No user-facing changes.

## [0.0.8] - 2009-10-27

### Added

- Added `{{PID}}` substitution to `restart_command`.

## [0.0.7] - 2009-10-24

### Added

- Self-daemonizing `start_command`s now run as the configured `uid` and `gid`.

## [0.0.6] - 2009-10-23

### Added

- Added monitoring of child processes with `monitor_children`.

### Changed

- Reworked the process state machine, adding the `starting`, `stopping` and `restarting` states.

### Fixed

- Fixed `start_grace_time`, `stop_grace_time` and `restart_grace_time` being ignored in favor of a hardcoded 3 seconds.
- Fixed global error handling catching `SystemExit`, which broke forking.
- Fixed a logger error in triggers.

## [0.0.5] - 2009-10-15

### Changed

- CPU and memory usage are now read from a single `ps axu` call per tick, which is more portable than reading `/proc`.
- Reduced log noise from `bluepill status`.

### Fixed

- Fixed deadlocks in triggers so flap detection and scheduled dispatches work.

## [0.0.4] - 2009-10-14

### Added

- Added ActiveSupport numeric and duration extensions so configs can use values like `5.minutes` and `3.megabytes`.
- `bluepill log` now prints a message when it starts tailing.

### Changed

- Required `activesupport` 2.3.4 or later.

## [0.0.3] - 2009-10-13

### Added

- Added the ability to run daemons as a different user.
- Added flap detection.
- Config attributes can now be read back in the DSL after they are set.

### Changed

- Loading a config now only waits for a previous bluepill daemon to die when one was actually running.

### Fixed

- Fixed bluepill forgetting a process's pid before the process had been started or killed.

## [0.0.2] - 2009-10-05

### Added

- Added the `quit` command.

### Changed

- Improved logging of watches and state transitions.
- Bluepill now creates its base directory structure on startup.

### Fixed

- Bluepill no longer claims to kill a process that is already dead.

## [0.0.1] - 2009-10-05

Initial release.

### Added

- Added a Ruby config DSL for defining an application with processes and groups.
- Added process monitoring with `start_command`, `stop_command`, `restart_command`, `pid_file`, daemonizing, and configurable grace times.
- Added CPU and memory usage conditions that trigger actions such as restarts.
- Added the `bluepill` CLI with the `load`, `status`, `start`, `stop`, `restart`, `unmonitor`, `quit` and `log` commands.
- Added syslog logging.

[unreleased]: https://github.com/bluepill-rb/bluepill/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/bluepill-rb/bluepill/compare/v0.1.6...v0.2.0
[0.1.6]: https://github.com/bluepill-rb/bluepill/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/bluepill-rb/bluepill/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/bluepill-rb/bluepill/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/bluepill-rb/bluepill/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/bluepill-rb/bluepill/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/bluepill-rb/bluepill/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/bluepill-rb/bluepill/compare/v0.0.70...v0.1.0
[0.0.70]: https://github.com/bluepill-rb/bluepill/compare/v0.0.69...v0.0.70
[0.0.69]: https://github.com/bluepill-rb/bluepill/compare/v0.0.68...v0.0.69
[0.0.68]: https://github.com/bluepill-rb/bluepill/compare/v0.0.67...v0.0.68
[0.0.67]: https://github.com/bluepill-rb/bluepill/compare/v0.0.66...v0.0.67
[0.0.66]: https://github.com/bluepill-rb/bluepill/compare/v0.0.65...v0.0.66
[0.0.65]: https://github.com/bluepill-rb/bluepill/compare/v0.0.64...v0.0.65
[0.0.64]: https://github.com/bluepill-rb/bluepill/compare/v0.0.63...v0.0.64
[0.0.63]: https://github.com/bluepill-rb/bluepill/compare/v0.0.62...v0.0.63
[0.0.62]: https://github.com/bluepill-rb/bluepill/compare/v0.0.61...v0.0.62
[0.0.61]: https://github.com/bluepill-rb/bluepill/compare/v0.0.60...v0.0.61
[0.0.60]: https://github.com/bluepill-rb/bluepill/compare/v0.0.59...v0.0.60
[0.0.59]: https://github.com/bluepill-rb/bluepill/compare/v0.0.58...v0.0.59
[0.0.58]: https://github.com/bluepill-rb/bluepill/compare/v0.0.57...v0.0.58
[0.0.57]: https://github.com/bluepill-rb/bluepill/compare/v0.0.56...v0.0.57
[0.0.56]: https://github.com/bluepill-rb/bluepill/compare/v0.0.55...v0.0.56
[0.0.55]: https://github.com/bluepill-rb/bluepill/compare/v0.0.54...v0.0.55
[0.0.54]: https://github.com/bluepill-rb/bluepill/compare/v0.0.53...v0.0.54
[0.0.53]: https://github.com/bluepill-rb/bluepill/compare/v0.0.52...v0.0.53
[0.0.52]: https://github.com/bluepill-rb/bluepill/compare/v0.0.51...v0.0.52
[0.0.51]: https://github.com/bluepill-rb/bluepill/compare/v0.0.50...v0.0.51
[0.0.50]: https://github.com/bluepill-rb/bluepill/compare/v0.0.49...v0.0.50
[0.0.49]: https://github.com/bluepill-rb/bluepill/compare/v0.0.48...v0.0.49
[0.0.48]: https://github.com/bluepill-rb/bluepill/compare/v0.0.47...v0.0.48
[0.0.47]: https://github.com/bluepill-rb/bluepill/compare/v0.0.46...v0.0.47
[0.0.46]: https://github.com/bluepill-rb/bluepill/compare/v0.0.45...v0.0.46
[0.0.45]: https://github.com/bluepill-rb/bluepill/compare/v0.0.44...v0.0.45
[0.0.44]: https://github.com/bluepill-rb/bluepill/compare/v0.0.43...v0.0.44
[0.0.43]: https://github.com/bluepill-rb/bluepill/compare/v0.0.42...v0.0.43
[0.0.42]: https://github.com/bluepill-rb/bluepill/compare/v0.0.40...v0.0.42
[0.0.40]: https://github.com/bluepill-rb/bluepill/compare/v0.0.39...v0.0.40
[0.0.39]: https://github.com/bluepill-rb/bluepill/compare/v0.0.38...v0.0.39
[0.0.38]: https://github.com/bluepill-rb/bluepill/compare/v0.0.37...v0.0.38
[0.0.37]: https://github.com/bluepill-rb/bluepill/compare/v0.0.36...v0.0.37
[0.0.36]: https://github.com/bluepill-rb/bluepill/compare/v0.0.35...v0.0.36
[0.0.35]: https://github.com/bluepill-rb/bluepill/compare/v0.0.34...v0.0.35
[0.0.34]: https://github.com/bluepill-rb/bluepill/compare/v0.0.33...v0.0.34
[0.0.33]: https://github.com/bluepill-rb/bluepill/compare/v0.0.32...v0.0.33
[0.0.32]: https://github.com/bluepill-rb/bluepill/compare/v0.0.31...v0.0.32
[0.0.31]: https://github.com/bluepill-rb/bluepill/compare/v0.0.30...v0.0.31
[0.0.30]: https://github.com/bluepill-rb/bluepill/compare/v0.0.28...v0.0.30
[0.0.28]: https://github.com/bluepill-rb/bluepill/compare/v0.0.27...v0.0.28
[0.0.27]: https://github.com/bluepill-rb/bluepill/compare/v0.0.26...v0.0.27
[0.0.26]: https://github.com/bluepill-rb/bluepill/compare/v0.0.25...v0.0.26
[0.0.25]: https://github.com/bluepill-rb/bluepill/compare/v0.0.24...v0.0.25
[0.0.24]: https://github.com/bluepill-rb/bluepill/compare/v0.0.23...v0.0.24
[0.0.23]: https://github.com/bluepill-rb/bluepill/compare/v0.0.22...v0.0.23
[0.0.22]: https://github.com/bluepill-rb/bluepill/compare/v0.0.21...v0.0.22
[0.0.21]: https://github.com/bluepill-rb/bluepill/compare/v0.0.20...v0.0.21
[0.0.20]: https://github.com/bluepill-rb/bluepill/compare/v0.0.19...v0.0.20
[0.0.19]: https://github.com/bluepill-rb/bluepill/compare/v0.0.18...v0.0.19
[0.0.18]: https://github.com/bluepill-rb/bluepill/compare/v0.0.17...v0.0.18
[0.0.17]: https://github.com/bluepill-rb/bluepill/compare/v0.0.16...v0.0.17
[0.0.16]: https://github.com/bluepill-rb/bluepill/compare/v0.0.15...v0.0.16
[0.0.15]: https://github.com/bluepill-rb/bluepill/compare/v0.0.14...v0.0.15
[0.0.14]: https://github.com/bluepill-rb/bluepill/compare/v0.0.13...v0.0.14
[0.0.13]: https://github.com/bluepill-rb/bluepill/compare/v0.0.12...v0.0.13
[0.0.12]: https://github.com/bluepill-rb/bluepill/compare/v0.0.11...v0.0.12
[0.0.11]: https://github.com/bluepill-rb/bluepill/compare/v0.0.10...v0.0.11
[0.0.10]: https://github.com/bluepill-rb/bluepill/compare/v0.0.9...v0.0.10
[0.0.9]: https://github.com/bluepill-rb/bluepill/compare/v0.0.8...v0.0.9
[0.0.8]: https://github.com/bluepill-rb/bluepill/compare/v0.0.7...v0.0.8
[0.0.7]: https://github.com/bluepill-rb/bluepill/compare/v0.0.6...v0.0.7
[0.0.6]: https://github.com/bluepill-rb/bluepill/compare/v0.0.5...v0.0.6
[0.0.5]: https://github.com/bluepill-rb/bluepill/compare/v0.0.4...v0.0.5
[0.0.4]: https://github.com/bluepill-rb/bluepill/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/bluepill-rb/bluepill/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/bluepill-rb/bluepill/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/bluepill-rb/bluepill/releases/tag/v0.0.1
