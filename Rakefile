#!/usr/bin/env rake

begin
	require 'hoe'
rescue LoadError
	abort "This Rakefile requires hoe (gem install hoe)"
end

GEMSPEC = 'sequel-inline_schema.gemspec'


Hoe.plugin :mercurial
Hoe.plugin :signing
Hoe.plugin :deveiate

Hoe.plugins.delete :rubyforge

hoespec = Hoe.spec 'sequel-inline_schema' do |spec|

	spec.readme_file = 'README.md'
	spec.history_file = 'History.md'
	spec.urls = {
		home:   'http://bitbucket.org/ged/sequel-inline_schema',
		code:   'http://bitbucket.org/ged/sequel-inline_schema',
		docs:   'http://deveiate.org/code/sequel-inline_schema',
		github: 'http://github.com/ged/sequel-inline_schema',
	}

	spec.extra_rdoc_files = FileList[ '*.rdoc', '*.md' ]
	spec.license 'BSD-3-Clause'

	spec.developer 'Michael Granger', 'ged@FaerieMUD.org'

	spec.dependency 'sequel', '~> 5.0'

	spec.dependency 'hoe-deveiate',            '~> 0.9', :developer
	spec.dependency 'simplecov',               '~> 0.13', :developer
	spec.dependency 'rdoc-generator-fivefish', '~> 0.3', :developer

	spec.require_ruby_version( '>=2.4.0' )
	spec.hg_sign_tags = true if spec.respond_to?( :hg_sign_tags= )
	spec.check_history_on_release = true if spec.respond_to?( :check_history_on_release= )

	spec.rdoc_locations << "deveiate:/usr/local/www/public/code/#{remote_rdoc_dir}"
end


ENV['VERSION'] ||= hoespec.spec.version.to_s

# Run the tests before checking in
task 'hg:precheckin' => [ :check_history, :check_manifest, :gemspec, :spec ]

task :test => :spec

# Rebuild the ChangeLog immediately before release
task :prerelease => 'ChangeLog'
CLOBBER.include( 'ChangeLog' )

desc "Build a coverage report"
task :coverage do
	ENV["COVERAGE"] = 'yes'
	Rake::Task[:spec].invoke
end
CLOBBER.include( 'coverage' )


# Use the fivefish formatter for docs generated from development checkout
if File.directory?( '.hg' )
	require 'rdoc/task'

	Rake::Task[ 'docs' ].clear
	RDoc::Task.new( 'docs' ) do |rdoc|

		rdoc.markup = 'markdown'
		rdoc.main = "README.md"
		rdoc.rdoc_files.include( "*.md", "ChangeLog", "lib/**/*.rb" )

		rdoc.generator = :fivefish
		rdoc.title = 'sequel-inline_schema'
		rdoc.rdoc_dir = 'doc'
	end
end

task :gemspec => GEMSPEC
file GEMSPEC => [ __FILE__, 'Manifest.txt' ]
task GEMSPEC do |task|
	spec = $hoespec.spec
	spec.files.delete( '.gemtest' )
	spec.signing_key = nil
	spec.cert_chain = ['certs/ged.pem']
	spec.version = "#{spec.version.bump}.0.pre#{Time.now.strftime("%Y%m%d%H%M%S")}"
	File.open( task.name, 'w' ) do |fh|
		fh.write( spec.to_ruby )
	end
end
CLOBBER.include( GEMSPEC.to_s )

task :default => :gemspec

