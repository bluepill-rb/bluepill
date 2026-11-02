require "etc"

module Bluepill
  module System
    # Set up the process that a command runs in: its user, groups, working
    # directory and environment
    #
    # Commands and Daemon include it, and System extends them, so these are
    # System's module functions.
    #
    # @api private
    module CommandSetup
      # Change to the command's working directory and set its environment
      #
      # @param [Hash{Symbol => Object}] options :working_dir and :environment
      #
      # @return [void]
      #
      # @api private
      def setup_command_environment(options)
        # Setting end PWD env emulates bash behavior when dealing with symlinks
        working_dir = options[:working_dir]
        Dir.chdir(ENV["PWD"] = working_dir.to_s) if working_dir
        environment = options[:environment]
        environment.each { |key, value| ENV[key.to_s] = value.to_s } if environment
      end

      # Switch to another user and groups, when bluepill runs as root
      #
      # With a uid, the command gets the user's own supplementary groups, the
      # way logging in as the user does, and the user's primary group unless
      # gid names another. supplementary_groups adds more groups to those.
      #
      # Be sure to call this from a fork, or it changes the user and groups of
      # the bluepill daemon itself.
      #
      # @param [String, nil] uid the user's name
      # @param [String, nil] gid the group's name
      # @param [Array<String>, nil] supplementary_groups more groups' names
      #
      # @return [void]
      #
      # @api private
      def drop_privileges(uid, gid, supplementary_groups)
        return unless ::Process::Sys.geteuid.zero?

        user = Etc.getpwnam(uid) if uid
        gid_num = join_groups(user, (Etc.getgrnam(gid).gid if gid))
        add_supplementary_groups(supplementary_groups)
        ::Process::Sys.setgid(gid_num) if gid_num
        switch_to_user(user) if user
      end

      # Join the user's groups, or just the named group without a user
      #
      # @param [Etc::Passwd, nil] user the user
      # @param [Integer, nil] gid_num the named group's id
      #
      # @return [Integer, nil] the primary group's id: the named group's, or
      #   else the user's own
      #
      # @api private
      def join_groups(user, gid_num)
        if user
          gid_num ||= user.gid
          ::Process.initgroups(user.name, gid_num)
        elsif gid_num
          ::Process.groups = [gid_num]
        end
        gid_num
      end

      # Add more groups to the ones the process is in
      #
      # @param [Array<String>, nil] supplementary_groups the groups' names
      #
      # @return [void]
      #
      # @api private
      def add_supplementary_groups(supplementary_groups)
        group_nums = (supplementary_groups || []).collect { |group| Etc.getgrnam(group).gid }
        ::Process.groups |= group_nums unless group_nums.empty?
      end

      # Become the user, once the groups are set, and point HOME at its home directory
      #
      # @param [Etc::Passwd] user the user
      #
      # @return [void]
      #
      # @api private
      def switch_to_user(user)
        ::Process::Sys.setuid(user.uid)
        ENV["HOME"] = user.dir if user.dir
      end
    end
  end
end
