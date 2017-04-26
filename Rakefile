require 'rake'
require 'rubygems/package'

desc "Run tests"
task :test, [:dbname, :user, :password] do |t, args|
  if args.dbname.nil?
    warn "Provide an existing database name to run the tests against"
    exit 1
  end
  Dir['test/test_*rb'].each {|testfile| load testfile }
  ARGV.replace [args.dbname, args.user, args.password]
end

desc "Build gem"
task :gem do
  Dir.chdir('ext') do
    %x(#{ENV['INFORMIXDIR']}/bin/esql -c informixc.ec)
  end
  spec = Gem::Specification.load('ruby-informix.gemspec')
  Gem::Package.build spec
end
