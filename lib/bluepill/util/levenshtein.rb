module Bluepill
  module Util
    # Return how many edits turn one string into another
    #
    # Counts the characters to insert, delete or replace (the Levenshtein
    # distance), a row of the table at a time. ProcessProxy uses it to
    # suggest the attribute closest to a misspelled one.
    #
    # @example
    #   Bluepill::Util.levenshtein_distance("start_comand", "start_command") # => 1
    #
    # @param [String] from the string to start from
    # @param [String] to the string to end at
    #
    # @return [Integer] the number of edits
    #
    # @api private
    def self.levenshtein_distance(from, to)
      row = (0..to.length).to_a
      from.each_char.with_index(1) do |from_char, i|
        next_levenshtein_row!(row, i, from_char, to)
      end
      row.fetch(-1)
    end

    # Turn a row of the distance table into the next one, in place
    #
    # Cell j becomes the fewest edits that turn the first from_length
    # characters of the from string into the first j characters of the to
    # string.
    #
    # @param [Array<Integer>] row the row for the characters before from_char
    # @param [Integer] from_length the number of from's characters, through
    #   from_char
    # @param [String] from_char the from string's next character
    # @param [String] to the string to end at
    #
    # @return [void]
    #
    # @api private
    def self.next_levenshtein_row!(row, from_length, from_char, to)
      diagonal = row.fetch(0)
      row[0] = from_length
      to.each_char.with_index(1) do |to_char, j|
        above = row.fetch(j)
        substitution = diagonal + (from_char.eql?(to_char) ? 0 : 1)
        row[j] = [above + 1, row.fetch(j - 1) + 1, substitution].min
        diagonal = above
      end
    end
    private_class_method :next_levenshtein_row!
  end
end
