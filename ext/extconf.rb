require 'mkmf'

env = nil
informixdir = ENV["INFORMIXDIR"]
MSWindows = /djgpp|(cyg|ms|bcc)win|mingw/

if informixdir.nil?
  warn "Set the Informix environment variables before installing this library"
  exit 1
end

esql = informixdir + "/bin/esql"
idefault = informixdir + "/incl/esql"
ldefault = [ informixdir + "/lib" ]
ldefault << informixdir + "/lib/esql" if RUBY_PLATFORM !~ MSWindows

dir_config("informix", idefault, ldefault)

if RUBY_PLATFORM =~ MSWindows
  $libs += informixdir + "/lib/isqlt09a.lib"
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


`#{env} #{esql} -e informixc.ec`
create_makefile("informixc")
