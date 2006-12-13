require 'mkmf'

env = nil
idefault = File.join(ENV["INFORMIXDIR"], "incl", "esql")
ldefault = File.join(ENV["INFORMIXDIR"], "lib")

if RUBY_PLATFORM =~ /mswin/
  $libs += " isqlt09a.lib"
else
  env = "/usr/bin/env"
  ldefault += ":" + File.join(ENV["INFORMIXDIR"], "lib", "esql")

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

dir_config("informix", idefault, ldefault)

`#{env} esql -e informix.ec`
create_makefile("informix")
