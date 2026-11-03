# frozen_string_literal: true

require "etc"

module Bluepill
  module System
    # Run a spawned command as another user and groups, with setpriv
    #
    # A Ruby that can't fork, such as JRuby, can't switch users or groups in
    # the child before it runs the command, as drop_privileges does. On
    # Linux, setpriv, from util-linux, does it instead: it switches, and runs
    # a small shell script that changes to the working directory and opens
    # the standard streams' files as the new user, as a forked child does,
    # and then replaces itself with the command, which keeps setpriv's pid.
    #
    # CommandSpawn includes it, so these are System's module functions.
    #
    # @api private
    module CommandPrivileges
      # What setpriv runs as the new user, with the working directory, the
      # files for standard input, output and error (each "" for none), and
      # the command
      SWITCHED_SCRIPT = <<~SH
        [ -z "$1" ] || cd "$1" || exit 1
        [ -z "$2" ] || exec <"$2"
        [ -z "$3" ] || exec >>"$3"
        if [ -n "$4" ] && [ "$4" = "$3" ]; then exec 2>&1; elif [ -n "$4" ]; then exec 2>>"$4"; fi
        shift 4
        exec "$@"
      SH

      # What setpriv runs as the new user to check that it can write a file
      WRITE_CHECK = ': >>"$1" && rm -f -- "$1"'

      # Return whether a command must run as another user or groups
      #
      # Bluepill only switches when it runs as root, as drop_privileges does.
      #
      # @param [CommandOptions] options its uid, gid and supplementary_groups
      #
      # @return [Boolean]
      #
      # @api private
      def switches_user?(options)
        return false unless ::Process::Sys.geteuid.zero?

        !(options.uid || options.gid).nil? || !(options.supplementary_groups || []).empty?
      end

      # Return whether setpriv is on the PATH
      #
      # @return [Boolean]
      #
      # @api private
      def setpriv?
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
          File.executable?(File.join(dir, "setpriv"))
        end
      end

      # Return the words that run a command with setpriv, as the new user
      #
      # @param [CommandOptions] options its uid, gid and supplementary_groups
      # @param [Array<String>] words the command, split into words
      # @param [String, nil] dir the directory to run in, or nil for
      #   bluepill's
      # @param [Array(String, String, String)] files the files for standard
      #   input, output and error, each nil for none
      #
      # @return [Array<String>]
      #
      # @api private
      def switched_command(options, words, dir:, files:)
        script = ["/bin/sh", "-c", SWITCHED_SCRIPT, "bluepill", dir.to_s, *files.collect(&:to_s)]
        ["setpriv", *setpriv_options(options), "--", *script, *words]
      end

      # Return whether a command's user and groups can write a file
      #
      # A forked daemon checks its pid file once it has switched, so a
      # spawned one checks it as the user too, with setpriv.
      #
      # @param [String] path the file
      # @param [CommandOptions] options its uid, gid and supplementary_groups
      #
      # @return [Boolean] true if the file could be created and removed
      #
      # @api private
      def switched_can_write?(path, options)
        Kernel.system("setpriv", *setpriv_options(options), "--", "/bin/sh", "-c", WRITE_CHECK, "bluepill", path)
      end

      # Return setpriv's options for a command's user and groups
      #
      # @param [CommandOptions] options its uid, gid and supplementary_groups
      #
      # @return [Array<String>] --reuid and --regid, if they change, and
      #   --groups, which every switch sets
      #
      # @api private
      def setpriv_options(options)
        user = switched_user(options)
        gid = switched_gid(options, user)
        groups = supplementary_gids(user, gid, options.supplementary_groups)
        args = ["--groups=#{groups.join(",")}"]
        args.unshift("--regid=#{gid}") if gid
        args.unshift("--reuid=#{user.uid}") if user
        args
      end

      # Return the user a command runs as
      #
      # @param [CommandOptions] options its uid
      #
      # @return [Etc::Passwd, nil] the user, or nil to stay root
      #
      # @api private
      def switched_user(options)
        uid = options.uid
        Etc.getpwnam(uid) if uid
      end

      # Return the group a command runs as
      #
      # @param [CommandOptions] options its gid
      # @param [Etc::Passwd, nil] user the user it runs as
      #
      # @return [Integer, nil] the named group's id, else the user's own,
      #   or nil to stay in root's
      #
      # @api private
      def switched_gid(options, user)
        gid = options.gid
        gid ? Etc.getgrnam(gid).gid : user&.gid
      end

      # Return the supplementary groups a command runs in
      #
      # They're what drop_privileges joins: with a user, the group it runs
      # as and every group the user is in, as initgroups gives, with only a
      # group, that group, and otherwise bluepill's own, and
      # supplementary_groups as well.
      #
      # @param [Etc::Passwd, nil] user the user it runs as
      # @param [Integer, nil] gid the group it runs as
      # @param [Array<String>, nil] supplementary_groups more groups' names
      #
      # @return [Array<Integer>] the groups' ids
      #
      # @api private
      def supplementary_gids(user, gid, supplementary_groups)
        extra = (supplementary_groups || []).collect { |name| Etc.getgrnam(name).gid }
        base = if user then [gid, *member_gids(user.name)]
        elsif gid then [gid]
        else ::Process.groups
        end
        (base + extra).compact.uniq
      end

      # Return the groups that list a user as a member
      #
      # @param [String] name the user's name
      #
      # @return [Array<Integer>] the groups' ids
      #
      # @api private
      def member_gids(name)
        Etc.enum_for(:group).select { |group| group.mem.include?(name) }.collect(&:gid)
      end

      # Return the environment variables that switching to a user sets
      #
      # @param [CommandOptions] options its uid
      #
      # @return [Hash{String => String}] HOME, the user's home directory, as
      #   switch_to_user sets it
      #
      # @api private
      def switched_environment(options)
        user = switched_user(options) if switches_user?(options)
        dir = user&.dir
        dir ? {"HOME" => dir} : {}
      end

      # Give a file the user and group that a command runs as
      #
      # A forked daemon writes its pid file once it has switched, so the
      # file is the user's. A spawned one's is bluepill's until this.
      #
      # @param [String] path the file
      # @param [CommandOptions] options its uid and gid
      #
      # @return [void]
      #
      # @api private
      def chown_to_switched(path, options)
        return unless switches_user?(options)

        user = switched_user(options)
        File.chown(user&.uid, switched_gid(options, user), path)
      end
    end
  end
end
