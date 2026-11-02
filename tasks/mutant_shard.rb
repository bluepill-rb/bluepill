require "open3"

# Splits the subjects mutant runs across CI runners (see
# .github/workflows/mutant.yml): every one, or those a diff touches.
module MutantShard
  # The subjects touched since ref (a revision), or every one without a ref
  def self.subjects(ref = nil)
    ref = nil if ref.to_s.empty?
    command = %w[bundle exec mutant environment subject list]
    command += ["--since", ref] if ref
    output, status = Open3.capture2(*command)
    raise "mutant couldn't list its subjects#{" touched since #{ref}" if ref}" unless status.success?

    # A subject's name has no space, which tells it apart from the
    # "Subjects in environment: N" line that starts the listing
    output.lines.collect(&:chomp).select { |line| line.start_with?("Bluepill") && !line.include?(" ") }
  end

  # Round robin rather than contiguous slices. Mutant lists subjects sorted,
  # so a class's slow subjects would otherwise all land in one shard.
  def self.shard(subjects, index, total)
    subjects.select.with_index { |_subject, position| position % total == index }
  end
end
