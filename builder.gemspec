require 'rubygems'

spec = Gem::Specification.new do |s|
  s.name = 'ruby-informix'
  s.version = '0.4.0'
  s.summary = 'Informix driver for Ruby'
  s.description = %{Ruby extension for connecting to IBM Informix Dynamic Server, written in ESQL/C.}
  s.files = ['informix.ec', 'COPYRIGHT', 'Changelog', 'README']
  s.autorequire = 'informix'
  s.has_rdoc = true
  s.extra_rdoc_files = ['informix.c']
  s.rdoc_options << '--title' << 'Ruby/Informix -- Informix driver for Ruby'
  s.author = 'Gerardo Santana Gomez Garrido'
  s.email = 'gerardo.santana@gmail.com'
  s.homepage = 'http://santanatechnotes.blogspot.com'
  s.rubyforge_project = 'ruby-informix'
  s.extensions << 'extconf.rb'
end

if $0 == __FILE__
  Gem::manage_gems
  Gem::Builder.new(spec).build
end
