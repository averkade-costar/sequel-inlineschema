#!/usr/bin/env rspec -cfd
#encoding: utf-8

require_relative '../../spec_helper'

require 'securerandom'

require 'loggability'
require 'pg'
require 'rspec'
require 'sequel/plugins/inline_schema'


describe Sequel::Plugins::InlineSchema do

	let( :db ) do
		Sequel.mock( host: 'postgres', columns: nil, logger: Loggability.logger )
	end

	let( :table ) do
		name = "test_table_%s" % [ SecureRandom.hex(8) ]
		name.to_sym
	end

	let( :model_class ) do
		mclass = Class.new( Sequel::Model )
		mclass.set_dataset( db[table] )
		mclass.plugin( :inline_schema )
		mclass
	end

	let( :valid_pg_attributes ) do
		[
			{
				name: "id",
				oid: 23,
				base_oid: nil,
				db_base_type: nil,
				db_type: "integer",
				default: "nextval('people_id_seq'::regclass)",
				allow_null: false,
				primary_key: true,
			},
			{
				name: "name",
				oid: 25,
				base_oid: nil,
				db_base_type: nil,
				db_type: "text",
				default: nil,
				allow_null: false,
				primary_key: false,
			},
			{
				name: "age",
				oid: 23,
				base_oid: nil,
				db_base_type: nil,
				db_type: "integer",
				default: nil,
				allow_null: false,
				primary_key: false,
			}
		]
	end

	let( :fake_db_fetcher ) do
		created = false
		Proc.new do |query|
			case query
			when /pg_attribute/
				created ? [] : valid_pg_attributes
			when /SELECT \* FROM "test_table/
				if created
					[{ id: 1, name: 'name', age: 20}]
				else
					raise PG::UndefinedTable.new( "No such table." )
				end
			when /SELECT NULL/
				if created
					{nil: nil}
				else
					raise PG::UndefinedTable.new("No such table.")
				end
			when /CREATE TABLE/
				created = true
			else
				fail "Unhandled query"
			end
		end
	end


	it "sets require_valid_table to false when it declares a schema" do
		model_class.set_schema { primary_key :id }
		expect( model_class.require_valid_table ).to be_falsey
	end


	it "doesn't set require_valid_table if require_table is true" do
		model_class.set_schema( require_table: true ) { primary_key :id }
		expect( model_class.require_valid_table ).to be_truthy
	end


	it "allows a model to create its table" do
		model_class.set_schema do
			primary_key :id
			String :name
			Integer :age
		end
		db.fetch = fake_db_fetcher

		model_class.create_table

		expect( db.sqls ).to include(
			%{CREATE TABLE "#{table}" ("id" serial PRIMARY KEY, "name" text, "age" integer)}
		)
	end


	it "allows a model to re-create its table" do
		model_class.set_schema do
			primary_key :id
			String :name
			Integer :age
		end
		db.fetch = fake_db_fetcher

		model_class.create_table!

		expect( db.sqls ).to include(
			%{DROP TABLE IF EXISTS "#{table}"},
			%{CREATE TABLE "#{table}" ("id" serial PRIMARY KEY, "name" text, "age" integer)}
		)
	end


	it "allows a model to create its table if it doesn't yet exist" do
		model_class.set_schema do
			primary_key :id
			String :name
			Integer :age
		end
		db.fetch = fake_db_fetcher

		model_class.create_table?

		expect( db.sqls ).to include(
			%{CREATE TABLE "#{table}" ("id" serial PRIMARY KEY, "name" text, "age" integer)}
		)
	end


	it "allows a model to declare its schema when it creates its table" do
		model_class.create_table do
			primary_key :id
			String :name
			Integer :age
		end

		expect( db.sqls ).to include(
			%{CREATE TABLE "#{table}" ("id" serial PRIMARY KEY, "name" text, "age" integer)}
		)
	end


	it "allows a model to determine whether its table exists or not" do
		model_class.table_exists?
		expect( db.sqls ).to include(
			%{SELECT NULL AS "nil" FROM "#{table}" LIMIT 1}
		)
	end


	it "allows a model to drop its table" do
		model_class.drop_table
		expect( db.sqls ).to include( %{DROP TABLE "#{table}"} )
	end


	describe "table-creation ordering" do

		let( :fake_db_fetcher ) do
			created = false
			Proc.new do |query|
				case query
				when /pg_attribute/
					created ? [] : valid_pg_attributes
				when /SELECT \* FROM "test_table/
					if created
						[{ id: 1, name: 'name'}]
					else
						raise PG::UndefinedTable.new( "No such table." )
					end
				when /SELECT NULL/
					if created
						{nil: nil}
					else
						raise PG::UndefinedTable.new("No such table.")
					end
				when /CREATE TABLE/
					created = true
				else
					fail "Unhandled query"
				end
			end
		end

		let( :base_class ) do
			mclass = Class.new( Sequel::Model )
			mclass.plugin( :inline_schema )
			mclass
		end

		let!( :artist_class ) do
			mclass = Class.new( base_class ) do
				def self::name; "Artist"; end
			end
			mclass.set_dataset( db[:artists] )
			mclass.set_schema do
				primary_key :id
				String :name
			end
			mclass
		end

		let!( :song_class ) do
			mclass = Class.new( base_class ) do
				def self::name; "Song"; end
			end
			mclass.set_dataset( db[:songs] )
			mclass.set_schema do
				primary_key :id
				String :name
				foreign_key :album_id, :albums
			end
			mclass.many_to_one :album, class: album_class
			mclass
		end

		let!( :album_class ) do
			mclass = Class.new( base_class ) do
				def self::name; "Album"; end
			end
			mclass.set_dataset( db[:albums] )
			mclass.set_schema do
				primary_key :id
				String :name
				foreign_key :artist_id, :artists
			end
			mclass.many_to_one :artist, class: artist_class
			mclass
		end



		it "returns model classes whose tables need to be created in dependency order" do
			db.fetch = fake_db_fetcher
			expect( base_class.uninstalled_tables ).to eq([
				artist_class, album_class, song_class
			])
		end


	end


	describe "hooks" do

		let( :model_class ) do
			class_obj = super()
			class_obj.singleton_class.send( :attr_accessor, :called )
			class_obj.called = {}
			class_obj
		end


		it "calls a hook before creating the model's table" do
			def model_class.before_create_table
				self.called[ :before_create_table ] = true
				super
			end

			model_class.create_table

			expect( model_class.called ).to include( :before_create_table )
		end


		it "allows cancellation of create_table from the before_create_table hook" do
			def model_class.before_create_table
				self.called[ :before_create_table ] = true
				cancel_action
			end

			expect {
				model_class.create_table
			}.to raise_error( Sequel::HookFailed, /hook failed/i )
		end


		it "allows cancellation of create_table with a message from the before_create_table hook" do
			def model_class.before_create_table
				self.called[ :before_create_table ] = true
				cancel_action( "Wait, don't create yet!" )
			end

			expect {
				model_class.create_table
			}.to raise_error( Sequel::HookFailed, "Wait, don't create yet!" )
		end


		it "allows cancellation of create_table with a Symbol from the before_create_table hook" do
			def model_class.before_create_table
				self.called[ :before_create_table ] = true
				cancel_action( :before_create_table )
			end

			expect {
				model_class.create_table
			}.to raise_error( Sequel::HookFailed, /before_create_table/ )
		end


		it "calls a hook after table creation" do
			def model_class.after_create_table
				super
				self.called[ :after_create_table ] = true
			end

			model_class.create_table

			expect( model_class.called ).to include( :after_create_table )
		end


		it "calls a hook before dropping the model's table" do
			def model_class.before_drop_table
				self.called[ :before_drop_table ] = true
				super
			end

			model_class.drop_table

			expect( model_class.called ).to include( :before_drop_table )
		end


		it "allows cancellation of drop_table from the before_drop_table hook" do
			def model_class.before_drop_table
				self.called[ :before_drop_table ] = true
				cancel_action
			end

			expect {
				model_class.drop_table
			}.to raise_error( Sequel::HookFailed, /hook failed/i )
		end


		it "allows cancellation of drop_table with a message from the before_drop_table hook" do
			def model_class.before_drop_table
				self.called[ :before_drop_table ] = true
				cancel_action( "Wait, don't drop yet!" )
			end

			expect {
				model_class.drop_table
			}.to raise_error( Sequel::HookFailed, "Wait, don't drop yet!" )
		end


		it "allows cancellation of drop_table with a Symbol from the before_drop_table hook" do
			def model_class.before_drop_table
				self.called[ :before_drop_table ] = true
				cancel_action( :before_drop_table )
			end

			expect {
				model_class.drop_table
			}.to raise_error( Sequel::HookFailed, /before_drop_table/ )
		end


		it "calls a hook after a class's table is dropped" do
			def model_class.after_drop_table
				super
				self.called[ :after_drop_table ] = true
			end

			model_class.drop_table

			expect( model_class.called ).to include( :after_drop_table )
		end

	end

end

