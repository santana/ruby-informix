require 'mkmf'

env = nil
informixdir = ENV["INFORMIXDIR"]

if informixdir.nil?
  informixdir = RUBY_PLATFORM =~ /mswin/ ? "C:\\informix" : "/usr/informix"
end

esql = File.join(informixdir, "bin", "esql")
idefault = File.join(informixdir, "incl", "esql")
ldefault = [ File.join(informixdir, "lib") ]
ldefault << File.join(informixdir, "lib", "esql") if RUBY_PLATFORM !~ /mswin/

dir_config("informix", idefault, ldefault)

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


`#{env} #{esql} -e informixc.ec`
create_makefile("informixc")
