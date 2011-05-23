# If there's a problem with ruby 1.9.2 and mysql2 gem, do this
# sudo install_name_tool -change libmysqlclient.18.dylib /usr/local/mysql/lib/libmysqlclient.18.dylib ~/.rvm/gems/ruby-1.9.2-p180/gems/mysql2-0.3.2/lib/mysql2/mysql2.bundle
# http://stackoverflow.com/questions/4546698/library-not-loaded-libmysqlclient-16-dylib-error-when-trying-to-run-rails-serve
require 'sinatra'
require 'thin'
require 'sequel'
require 'mysql2'
require 'json'

@current_user_id = nil
@DB = nil

# Connect to database
before do
  if @DB.nil?
    @DB = Sequel.connect(:adapter=>'mysql2', :host=>'localhost', :database=>'ohsnap',
      :user=>'root', :password=>'')
  end
end

# Basic authentication using access_token
get '/*' do
  dataset = @DB["SELECT id FROM users WHERE access_token = ?", params[:access_token]]
  @current_user_id = dataset.first[:id]
  pass unless @current_user_id.nil?
  "Sorry, you are not authenticated."
end

# Get album stream
# Show a list of albums for the authenticated user
# @param REQUIRED access_token
# @param OPTIONAL q (query search by album name)
# Sample url: http://localhost:4567/albums?access_token=[insertLocaltoken]
get '/album/index' do

  query = "
    select a.*
    from albums a
    join albums_users map on a.id = map.album_id
    where map.user_id = 1
    order by updated_at desc
  "
  
  query = "select * from users"
  response = []
  @DB.fetch(query) do |row|
      albums_hash = {
        :album_name => row[:name],
        :last_five_snaps => nil,
        :updated_at => nil
      }
      response << albums_hash
  end
  
  # content_type :json
  #   response.to_json
  content_type :json
  @DB["select * from users"].to_hash(:facebook_id, :third_party_id).to_json
  
end

# Get snap stream of a particular album
# Show a list of snaps from an album
# @param REQUIRED album_id
# @param REQUIRED access_token
get '/album/:album_id' do
  
  query = "
    select *
    from snaps s
    where album_id = #{params[:album_id]}
    order by created_at desc
  "
  @DB.fetch(query) do |row|
      albums_hash = {
        :album_name => row[:name],
        :last_five_snaps => nil,
        :updated_at => nil
      }
      response << albums_hash
  end
  
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
#   `image0` int(11) DEFAULT NULL,
#   `image1` int(11) DEFAULT NULL,
#   `image2` int(11) DEFAULT NULL,
#   `image3` int(11) DEFAULT NULL,
#   `image4` int(11) DEFAULT NULL,
#   `image_update_index` int(2) DEFAULT NULL COMMENT 'last image updated',
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

