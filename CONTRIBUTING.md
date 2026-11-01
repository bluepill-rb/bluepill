Contributing
------------

To ease development and troubleshooting, a simple vagrant environment exists [here](https://github.com/iancoffey/chef_bluepill_devel). A "vagrant up" should do the trick.

As more OS options are added, this should also simplify the steps necessary to reproduce odd issues.

Type checking
-------------

The RBS signatures in `sig/bluepill.rbs` ship with the gem, and CI checks `lib` against them with [Steep](https://github.com/soutaro/steep) in strict mode. Steep needs Ruby 3.3 or newer. To run the check locally:

    bundle exec rake steep

This installs the signatures of the dependencies into `.gem_rbs_collection`, validates the signatures and runs `steep check`. `sig-vendor` has stubs for the dependencies that publish no signatures. Update `sig/bluepill.rbs` when you change a method in `lib`.

Mutation testing
----------------

CI runs [mutant](https://github.com/mbj/mutant) on Ruby 4.0, and every mutant must be killed. Mutant needs Ruby 3.3 or newer. To run it on every subject locally:

    bundle exec rake mutant

Or only on the subjects you changed since `master`:

    bundle exec mutant run --since master

CI only mutates the subjects that a push or pull request changes, split into shards that run in parallel. To mutate every subject in CI, run the Mutant workflow from the Actions tab.
