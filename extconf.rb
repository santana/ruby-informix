require 'mkmf'

dir_config("informix")

env = nil
if RUBY_PLATFORM =~ /mswin/
  $libs += " isqlt09a.lib"
else
  env = "/usr/bin/env"
  %w(ifsql ifasf ifgen ifos ifgls).each do |lib|
    $libs += " " + format(LIBARG, lib)
  end
  $LIBPATH.each {|path|
    checkapi = path + "/checkapi.o"
    if File.exist?(checkapi)
      $libs += " " + checkapi
      break
    end
  }
end

`#{env} esql -e informix.ec`
create_makefile("informix")
