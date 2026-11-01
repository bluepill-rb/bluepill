Contributing
------------

To ease development and troubleshooting, a simple vagrant environment exists [here](https://github.com/iancoffey/chef_bluepill_devel). A "vagrant up" should do the trick.

As more OS options are added, this should also simplify the steps necessary to reproduce odd issues.

Type checking
-------------

The RBS signatures in `sig/bluepill.rbs` ship with the gem, and CI checks `lib` against them with [Steep](https://github.com/soutaro/steep) in strict mode. Steep needs Ruby 3.3 or newer. To run the check locally:

    bundle exec rake steep

This installs the signatures of the dependencies into `.gem_rbs_collection`, validates the signatures and runs `steep check`. `sig-vendor` has stubs for the dependencies that publish no signatures. Update `sig/bluepill.rbs` when you change a method in `lib`.
