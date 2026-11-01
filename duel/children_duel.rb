# frozen_string_literal: true

require_relative 'duel_helper'

# Bluepill finds a process's children in the tick's ps table, for
# monitor_children and for checks with include_children
master = PsListing::MASTER

duel('children: a process with none, among 300', **table_hooks(300)) { Bluepill::System.get_children(100) }
duel('children: 4 workers, among 300', **table_hooks(300, workers: 4)) { Bluepill::System.get_children(master) }
duel('children: 8 workers with 8 children, among 300', **table_hooks(300, workers: 8, grandchildren: 8)) do
  Bluepill::System.get_children(master)
end
duel('children: 32 workers, among 1,000', **table_hooks(1_000, workers: 32)) { Bluepill::System.get_children(master) }

duel('cpu: one process, among 300', **table_hooks(300, workers: 4)) { Bluepill::System.cpu_usage(master, false) }
duel('memory: a process and its 4 workers, among 300', **table_hooks(300, workers: 4)) do
  Bluepill::System.memory_usage(master, true)
end
