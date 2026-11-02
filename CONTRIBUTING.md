Contributing
------------

To ease development and troubleshooting, a simple vagrant environment exists [here](https://github.com/iancoffey/chef_bluepill_devel). A "vagrant up" should do the trick.

As more OS options are added, this should also simplify the steps necessary to reproduce odd issues.

Running from a checkout
-----------------------

To run bluepill with the code in your checkout instead of an installed gem:

    bundle exec bin/bluepill --no-privileged load path/to/app.pill

The daemon it starts runs the checkout's code too. Drop `--no-privileged` when you run it as root. `spec/smoke.sh` runs bluepill this way for real, as a daemon and in the foreground, and CI runs it on every Ruby:

    bash spec/smoke.sh

Type checking
-------------

The RBS signatures in `sig/` ship with the gem, and CI checks `lib` against them with [Steep](https://github.com/soutaro/steep) in strict mode. Steep needs Ruby 3.3 or newer. To run the check locally:

    bundle exec rake steep

This installs the signatures of the dependencies into `.gem_rbs_collection`, validates the signatures and runs `steep check`. `sig-vendor` has stubs for the dependencies that publish no signatures. Update the signatures when you change a method in `lib`: `sig/bluepill.rbs` has the shared types, and `sig/bluepill/` has a file for each part of the gem.

Mutation testing
----------------

CI runs [mutant](https://github.com/mbj/mutant) on Ruby 4.0, and every mutant must be killed. Mutant needs Ruby 3.3 or newer. To run it on every subject locally:

    bundle exec rake mutant

Or only on the subjects you changed since `master`:

    bundle exec mutant run --since master

CI only mutates the subjects that a push or pull request changes, split into shards that run in parallel. To mutate every subject in CI, run the Mutant workflow from the Actions tab.

Performance
-----------

[Duel](https://github.com/sferik/duel-ruby) guards against changes that make bluepill slower. The benchmarks in `duel/` cover what bluepill does every tick: parsing `ps`, finding children, running checks, ticking processes, and logging. Duel needs Ruby 3.4 or newer. To compare your branch with `master`:

    bundle exec duel

A pull request that makes a benchmark slower, allocate more, or leave more objects alive fails the Perf workflow. To check that new benchmarks pass on unchanged code, run `bundle exec duel --force`, and to run some of them, add `--filter "^watch:"`.
