# $Id: Rakefile,v 1.3 2008/03/16 02:18:39 santana Exp $

require 'rubygems'
require 'rake'
require 'rake/gempackagetask'

PKG_NAME = 'ruby-informix'
PKG_VERSION = '0.7.0'
PKG_FILES = Dir["test/*rb"] + %w{ext/informixc.ec ifx_except.rb informix.rb} +
            %w{INSTALL COPYRIGHT Changelog README}

spec = Gem::Specification.new do |s|
  s.name = PKG_NAME
  s.version = PKG_VERSION
  s.summary = 'Ruby extension for IBM Informix'
  s.description = 'Ruby extension for connecting to IBM Informix 7.x and above'
  s.files = PKG_FILES
  s.require_path = '.'
  s.autorequire = 'informix'
  s.has_rdoc = true
  s.rdoc_options << '--title' << 'Ruby/Informix -- Ruby extension for IBM Informix'
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
