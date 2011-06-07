# Evaulate gzip response type (low priority)

# Id is always string
# Counts are always ints

require 'sinatra'
require 'thin'
require 'sequel'
require 'mysql2'
require 'json'

require 'datamapper'
require 'dm-paperclip'
require 'haml'
require 'fileutils'
require 'aws/s3'

APP_ROOT = File.expand_path(File.dirname(__FILE__))

@current_user_id = nil
@DB = nil

# Connect to database
before do
  
  DataMapper::setup(:default, 'mysql://ohsnap:ohsnap@127.0.0.1/ohsnap')
  
  if @DB.nil?
    @DB = Sequel.connect(:adapter=>'mysql2', :host=>'localhost', :database=>'ohsnap',
      :user=>'root', :password=>'')
  end
end

class Resource
  include DataMapper::Resource
  include Paperclip::Resource

  property :id,     Serial

  # has_attached_file :file,
  #                   :url => "/:attachment/:id/:style/:basename.:extension",
  #                   :path => "#{APP_ROOT}/public/:attachment/:id/:style/:basename.:extension"
  
  has_attached_file :photo,
    :storage => :s3,
    # :s3_credentials => "#{APP_ROOT}/config/s3.yml",
    :s3_credentials   => {
                      :access_key_id      => 'AKIAJRFSK3RWQ7XLGNFA',
                      :secret_access_key  => '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',
                      :bucket             => 'scrapboard'
                      },
    :path => "/:class/:attachment/:id/:style/:filename",
    :url => "/:class/:attachment/:id/:style_:basename.:extension",
    :default_url => "/:class/:attachment/missing_:style.png",
    :whiny_thumbnails => true,
    :styles => { :thumb => "480x480#" , :square => "100x100#" , :preview => "600x600#" }
end

def make_paperclip_mash(file_hash)
  mash = Mash.new
  mash['tempfile'] = file_hash[:tempfile]
  mash['filename'] = file_hash[:filename]
  mash['content_type'] = file_hash[:type]
  mash['size'] = file_hash[:tempfile].size
  mash
end


# curl -Fphoto=@smiley.jpg http://localhost:4567/test
# curl -Fphoto=@oranges.jpg http://localhost:4567/test
# curl -Fphoto=@greenapples.jpg http://localhost:4567/test
post '/test' do

  puts params[:photo]

  if params[:photo]
  
    filename = params[:photo][:filename]
    file = params[:photo][:tempfile]
  
    AWS::S3::Base.establish_connection!( :access_key_id => "AKIAJRFSK3RWQ7XLGNFA", :secret_access_key => "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")
    awsresponse = AWS::S3::S3Object.store(filename, open(file), "scrapboard", :access => :public_read)
    # puts awsresponse.etag
   
    db_snaps = @DB.from(:snaps)
    dbresponse = db_snaps.insert(:album_id=>1, :user_id=>1234, :photo_file_name=>filename, :created_at => Time.now)
    puts dbresponse.insert
    "Image uploaded"
  else
    "You have to choose a file"
  end
  
  # halt 409, "File seems to be emtpy" unless params[:photo][:tempfile].size > 0
  # @resource = Resource.new(:photo => make_paperclip_mash(params[:photo]))
  # halt 409, "There were some errors processing your request...\n#{resource.errors.inspect}" unless @resource.save
  # haml :upload
  
end

# post '/upload' do
#   halt 409, "File seems to be emtpy" unless params[:file][:tempfile].size > 0
#   @resource = Resource.new(:file => make_paperclip_mash(params[:file]))
#   halt 409, "There were some errors processing your request...\n#{resource.errors.inspect}" unless @resource.save
# 
#   haml :upload
# end



# Registration/sign-up
post '/register' do
  
end

# Basic authentication using access_token
# get '/*' do
#   dataset = @DB["SELECT id FROM users WHERE access_token = ?", params[:access_token]]
#   if dataset.first.nil?
#     "Sorry, you are not authenticated."
#   else
#     @current_user_id = dataset.first[:id]
#     pass unless @current_user_id.nil?
#   end
# 
# end

# Get album stream
# Show a list of albums for the authenticated user
# @param REQUIRED access_token
# @param OPTIONAL q (query search by album name)
# @param OPTIONAL since
# @param OPTIONAL until
# Sample url: http://localhost:4567/v1/album/index?access_token=[insertLocaltoken]
get '/:version/album/index' do

  #Paging parameter require time bounds and limit
  time_bounds = ""
  if params[:since]!=nil && params[:until]==nil
    time_bounds = " and a.updated_at>from_unixtime(#{params[:since].to_i})"
  # pass until, then get everything < until
  elsif params[:since]==nil && params[:until]!=nil
    time_bounds = " and a.updated_at<from_unixtime(#{params[:until].to_i})"
  else
  end

  query = "
    select a.*
    from albums a
    join albums_users map on a.id = map.album_id
    where map.user_id = 1
    " + time_bounds + "
    order by a.updated_at desc
  "
  response = []
  @DB.fetch(query) do |row|
      
      images = [row[:image0], row[:image1], row[:image2], row[:image3], row[:image4]]
      
      albums_hash = {
        :album_name => row[:name],
        :photo_count => row[:photo_count],
        :images => images,
        :created_at => row[:created_at],
        :updated_at => row[:updated_at]
      }
      response << albums_hash
  end
  
  # Paging
  paging_hash = {}
  paging_hash[:since] = response.first[:updated_at].nil? ? Time.now.to_i : response.first[:updated_at]
  paging_hash[:until] = response.last[:updated_at].nil? ? Time.now.to_i : response.first[:updated_at]
  
  content_type :json
    response.to_json
  # content_type :json
  # @DB["select * from users"].to_hash(:facebook_id, :third_party_id).to_json
  
  # :participant_list
      # participants_hash[row['album_id'].to_s]
  # :pregen_participant_string (up to 6 people and total count of first degree friends)
      # 3 ppl and 123 more (estimate 60 characters including the "and...")
      # make it dynamic so we can pass more ppl depending on client
      # second degree is always in the 'and more' section
      # list of ppl is sorted by first degree last update/add time
  
  # TODO: logging
  
end

# Create album
# Insert into albums table
# Insert into albums_users table of invited users
# Insert into photo (see paperclip source code)
# @param REQUIRED photo
# @param OPTIONAL friends (comma separated string)
# @param OPTIONAL name
# Sample url: http://localhost:4567/v1/album/create?photo=[the_photo_url]
get '/:version/album/create' do
  
  db_albums = @DB.from(:albums)
  db_albums_users = @DB.from(:albums_users)
  db_snaps = @DB.from(:snaps)  
  
  # Create album
  album_id = db_albums.insert(:name=>params[:name], :updated_at=>Time.now, :created_at=>Time.now)

  # Create snap
  snap_id = db_snaps.insert(:album_id=>album_id, :user_id=>104938, :photo_file_name=>params[:photo])
  
  # Set album image0 as first image
  db_albums.filter('id = ?', album_id).update(:image0 => snap_id)
  
  # Create albums_users mapping
  db_albums_users.insert_ignore.multi_insert([{:album_id=>1, :user_id=>104938}])
  
end


# Get snap stream of a particular album
# Show a list of snaps from an album
# @param REQUIRED album_id
# @param REQUIRED access_token
# Sample: http://localhost:4567/v1/album/1/index?access_token=[insertLocaltoken]
get '/:version/album/:album_id/index' do
  
  query = "
    select *
    from snaps s
    where album_id = #{params[:album_id]}
    order by created_at desc
  "
  response = []
  @DB.fetch(query) do |row|
      albums_hash = {
        :user_id => row[:user_id].to_s,
        :message => row[:message],
        :updated_at => row[:updated_at]
      }
      response << albums_hash
  end
  
  # Paging
  paging_hash = {}
  paging_hash[:since] = response.first[:updated_at].nil? ? Time.now.to_i : response.first[:updated_at]
  paging_hash[:until] = response.last[:updated_at].nil? ? Time.now.to_i : response.first[:updated_at]
  
  content_type :json
    response.to_json
  
end

# Create snap
# Insert into snap table
# Update count in albums table and image cache and updated_at
# @param REQUIRED album_id
# @param REQUIRED photo (binary photo)
# @param OPTIONAL caption
post '/:version/snap/create' do
  
end

# Delete snap (low priority)
# @param REQUIRED snap_id
post '/:version/snap/delete' do
  
end

# Add friend to album
# @param REQUIRED album_id
# @param REQUIRED friends (comma separated string)
post '/:version/album/adduser' do
  
end

# Delete user from album; only can remove self
# @param REQUIRED album_id
post '/:version/album/removeuser' do
  
end




# Test route
# Sample url: http://localhost:4567/hello/thomas?access_token=5ce83e653ef8581d93ea0bf6e9a5db195b9c22bcce6e40e675a7ea75269083d960fdd7f0d0d13504080876a416706e528245c0a4e606e07675ccd573b709c25e
get '/hello/:name' do
    # matches "GET /hello/foo" and "GET /hello/bar"
    # params[:name] is 'foo' or 'bar'
    "Hello #{params[:name]}!"
    "Authenticated as user #{@current_user_id}"
end


# CREATE TABLE `albums` (
#   `id` int(11) NOT NULL AUTO_INCREMENT,
#   `name` varchar(255) DEFAULT NULL,
#   `photo_count` int(11) DEFAULT NULL,  
#   `image0` varchar(255) DEFAULT NULL,
#   `image1` varchar(255) DEFAULT NULL,
#   `image2` varchar(255) DEFAULT NULL,
#   `image3` varchar(255) DEFAULT NULL,
#   `image4` varchar(255) DEFAULT NULL,
#   `created_at` datetime DEFAULT NULL,
#   `updated_at` datetime DEFAULT NULL,
#   PRIMARY KEY (`id`),
#   KEY `idx_name` (`name`),
#   KEY `idx_updated_at` (`updated_at`)
# ) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8

# CREATE TABLE `snaps` (
#   `id` int(11) NOT NULL AUTO_INCREMENT,
#   `album_id` bigint(20) DEFAULT '0',
#   `user_id` bigint(20) DEFAULT '0',
#   `message` varchar(255) DEFAULT NULL,
#   `media_type` varchar(0) DEFAULT NULL,
#   `photo_file_name` varchar(255) DEFAULT NULL,
#   `photo_content_type` varchar(255) DEFAULT NULL,
#   `photo_file_size` int(11) DEFAULT NULL,
#   `video_file_name` varchar(255) DEFAULT NULL,
#   `video_content_type` varchar(255) DEFAULT NULL,
#   `video_file_size` int(11) DEFAULT NULL,
#   `lat` decimal(20,16) DEFAULT NULL,
#   `lng` decimal(20,16) DEFAULT NULL,
#   `created_at` datetime DEFAULT NULL,
#   `updated_at` datetime DEFAULT NULL,
#   PRIMARY KEY (`id`),
#   KEY `idx_album_id` (`album_id`),
#   KEY `idx_user_id` (`user_id`)
# ) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8

# Command line loop
# while :
# do
#   curl http://localhost:4567/album/index?access_token=5ce83e653ef8581d93ea0bf6e9a5db195b9c22bcce6e40e675a7ea75269083d960fdd7f0d0d13504080876a416706e528245c0a4e606e07675ccd573b709c25e
#   sleep 1
# done

# Notes

# Return json
# http://nathanhoad.net/how-to-return-json-from-sinatra


# If there's a problem with ruby 1.9.2 and mysql2 gem, do this
# sudo install_name_tool -change libmysqlclient.18.dylib /usr/local/mysql/lib/libmysqlclient.18.dylib ~/.rvm/gems/ruby-1.9.2-p180/gems/mysql2-0.3.2/lib/mysql2/mysql2.bundle
# http://stackoverflow.com/questions/4546698/library-not-loaded-libmysqlclient-16-dylib-error-when-trying-to-run-rails-serve



# How to use Sinatra and Paperclip
# https://gist.github.com/291877
