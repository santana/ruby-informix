require 'rake'

desc "Run tests"
task :test, [:dbname, :user, :password] do |t, args|
  if args.dbname.nil?
    warn "Provide an existing database name to run the tests against"
    exit 1
  end
  Dir['test/test_*rb'].each {|testfile| load testfile }
  ARGV.replace [args.dbname, args.user, args.password]
end
