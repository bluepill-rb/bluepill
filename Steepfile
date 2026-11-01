D = Steep::Diagnostic

target :lib do
  # sig ships with the gem. sig-vendor has stubs for dependencies that
  # publish no signatures, and stays out of the gem.
  signature 'sig', 'sig-vendor'

  check 'lib'

  configure_code_diagnostics(D::Ruby.strict)
end
