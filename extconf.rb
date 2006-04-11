require 'mkmf'

dir_config("informix")

if RUBY_PLATFORM =~ /mswin/
  $libs += " isqlt09a.lib"
else
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

`esql -e informix.ec`
create_makefile("informix")
