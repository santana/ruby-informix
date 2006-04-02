require 'mkmf'

dir_config("informix")
have_library("isqlt09a", "")
create_makefile("informix")
