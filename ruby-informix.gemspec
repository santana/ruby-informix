PKG_NAME = 'ruby-informix'
PKG_VERSION = '0.8.1'
PKG_FILES = %w{ext/informixc.ec lib/informix.rb} + Dir["lib/informix/*"] +
            Dir["test/*rb"] + %w{COPYRIGHT Changelog README}

spec = Gem::Specification.new do |s|
  s.name = PKG_NAME
  s.version = PKG_VERSION
  s.summary = 'Ruby library for IBM Informix'
  s.description = 'Ruby library for connecting to IBM Informix 7 and above'
  s.files = PKG_FILES
  s.require_path = 'lib'
  s.has_rdoc = true
  s.rdoc_options << '--title' << "Ruby/Informix -- #{s.summary}" <<
                    '--exclude' << 'test' << '--exclude' << 'extconf.rb' <<
                    '--inline-source' << '--line-numbers' <<
                    '--main' << 'README'
  s.extra_rdoc_files << 'README' << 'ext/informixc.c'
  s.author = 'Gerardo Santana Gomez Garrido'
  s.email = 'gerardo.santana@gmail.com'
  s.homepage = 'http://ruby-informix.rubyforge.org/'
  s.rubyforge_project = PKG_NAME
  s.extensions << 'ext/extconf.rb'
end
