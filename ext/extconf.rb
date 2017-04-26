require 'mkmf'

env = libs = nil
informixdir = ENV["INFORMIXDIR"]
MSWindows = /djgpp|(cyg|ms|bcc)win|mingw/

if informixdir.nil?
  warn "Set the Informix environment variables before installing this library"
  exit 1
end

esql = File.join(informixdir, 'bin', 'esql')
idefault = File.join(informixdir, 'incl', 'esql')
ldefault = [ File.join(informixdir, 'lib') ]
ldefault << File.join(informixdir, 'lib', 'esql') if RUBY_PLATFORM !~ MSWindows

dir_config("informix", idefault, ldefault)

if RUBY_PLATFORM =~ MSWindows
  libs += File.join(informixdir, 'lib', 'isqlt09a.lib')
else
  env = "/usr/bin/env"

  %w(ifsql ifasf ifgen ifos ifgls).each do |lib|
    libs += " " + format(LIBARG, lib)
  end
  $LIBPATH.each do |path|
    checkapi = File.join(path, 'checkapi.o')
    if File.exist?(checkapi)
      libs += " " + checkapi
      break
    end
  end
end

%x{#{env} #{esql} -e informixc.ec}
create_makefile("informixc")
