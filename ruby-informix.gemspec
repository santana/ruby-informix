spec = Gem::Specification.new do |s|
  s.name = 'ruby-informix'
  s.version = '0.8.2'
  s.summary = 'Ruby library for IBM Informix'
  s.description = 'Ruby library for connecting to IBM Informix 7 and above'
  s.license = 'BSD-3-Clause'
  s.files = %w{ext/informixc.ec lib/informix.rb} + Dir["lib/informix/*"] +
            Dir["test/*rb"] + %w{COPYRIGHT Changelog README.md}
  s.require_path = 'lib'
  s.has_rdoc = true
  s.rdoc_options << '--title' << "Ruby/Informix -- #{s.summary}" <<
                    '--exclude' << 'test' << '--exclude' << 'extconf.rb' <<
                    '--inline-source' << '--line-numbers' <<
                    '--main' << 'README.md'
  s.extra_rdoc_files << 'README.md' << 'ext/informixc.c'
  s.author = 'Gerardo Santana Gomez Garrido'
  s.email = 'gerardo.santana@gmail.com'
  s.homepage = 'http://ruby-informix.rubyforge.org/'
  s.rubyforge_project = 'ruby-informix'
  s.extensions << 'ext/extconf.rb'
end
