# $Id: Rakefile,v 1.1 2007/12/27 08:55:17 santana Exp $

require 'rubygems'
require 'rake'
require 'rake/gempackagetask'

PKG_NAME = 'ruby-informix'
PKG_VERSION = '0.6.3'
PKG_FILES = Dir["ext/*.ec"] + Dir["ext/*.h"] + Dir["test/*rb"] +
            %w{INSTALL COPYRIGHT Changelog README}

spec = Gem::Specification.new do |s|
  s.name = PKG_NAME
  s.version = PKG_VERSION
  s.summary = 'Informix extension for Ruby'
  s.description = %{Ruby extension for connecting to IBM Informix Dynamic Server, written in ESQL/C.}
  s.files = PKG_FILES
  s.require_path = 'ext'
  s.autorequire = 'informix'
  s.has_rdoc = true
  s.rdoc_options << '--title' << 'Ruby/Informix -- Informix extension for Ruby'
  s.author = 'Gerardo Santana Gomez Garrido'
  s.email = 'gerardo.santana@gmail.com'
  s.homepage = 'http://santanatechnotes.blogspot.com'
  s.rubyforge_project = PKG_NAME
  s.extensions << 'ext/extconf.rb'
end

Rake::GemPackageTask.new(spec) do |p|
  p.gem_spec = spec
  p.need_tar_gz = true
  p.need_zip = true
end
