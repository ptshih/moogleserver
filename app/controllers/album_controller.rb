class AlbumController < ApplicationController
  before_filter do |controller|
    # This will set the @version variable
    controller.load_version(["v1","v2","v3"])
    # controller.authenticate_token # sets the @current_user var based on passed in access_token
  end

  # Show a list of albums for the authenticated user (or optionally any user if public)
  # @param REQUIRED list_type "all", "contributing"
  # @param REQUIRED access_token
  # @param OPTIONAL q (query search by album name)
  # Authentication required
  # Sample url: http://localhost:3000/v1/albums?list_type=contributing&access_token=[insertLocaltoken]&format=xml
  def index
    self.authenticate_token

    Rails.logger.info request.query_parameters.inspect
    api_call_start = Time.now.to_f

    ########
    # NOTE #
    ########
    # All response_hash objects should follow this format...
    # object_hash is a hash with a key called :data
    # object_hash[:data] has an array of hashes that represent a single object (response_array contains many row_hash)
    # object_hash[:paging] is optional and has a key :since and key :until
    # :since is the :timestamp of the first object in response_array
    # :until is the :timestamp of the last object in response_array
    # A subhash inside row_hash (i.e. participants_hash) will have the same format, just no :paging

    
    # Getting friend's list
    friend_id_array = {}
    query = " select friend_id, friend_name from friendships where user_id = #{@current_user.id}"
    mysqlresults = ActiveRecord::Base.connection.execute(query)
    mysqlresults.each(:as => :hash) do |row|
      friend_hash = {
        :id => row['friend_id'],
        :name => row['friend_name']
      }
      friend_id_array[row['friend_id'].to_s] = friend_hash
    end

    # Filter to show only albums where you are contributing
    album_id_array = []
    if params[:list_type] == 'contributing'
      query = "select album_id from albums_users where user_id = #{@current_user.id}"
    # show all albums of your first degree connections
    else
      query = " select album_id
                from albums_users
                where user_id in (select friend_id from friendships where user_id=#{@current_user.id})
                  or user_id=#{@current_user.id}"
    end
    mysqlresults = ActiveRecord::Base.connection.execute(query)
    mysqlresults.each(:as => :hash) do |row|
      album_id_array << row['album_id']
    end
    
    #
    # WARNING!!!
    # CHECK FOR EMPTY ARRAY
    # DEFAULT TO "0" for now
    if album_id_array.length==0
      album_id_array << "0"
    end
    album_id_string = album_id_array.uniq.join(',')
    puts "this is the album #{album_id_string}"
    
    ###
    # Getting participants
    ###
    participants_hash = {}
    query = "
      select au.album_id, u.id, u.name, u.first_name, u.picture_url
      from albums_users au
      join users u on au.user_id = u.id
      where au.album_id in (#{album_id_string})
    "
    mysqlresults = ActiveRecord::Base.connection.execute(query)
    mysqlresults.each(:as => :hash) do |row|
      if !participants_hash.has_key?(row['album_id'].to_s)
        participants_hash[row['album_id'].to_s] = []
      end
      participant_hash = {
        :id => row['id'],
        :name => row['name'],
        :first_name => row['first_name'],
        :picture_url => row['picture_url']
      }
      participants_hash[row['album_id'].to_s] << participant_hash
    end

    ###
    # Getting album stats
    # comments, likes
    ###
    # album_stats = { 'comment'=>{}, 'like'=>{}}
    # query = "select album_id, count(*) as thecount from snap_comments group by 1"
    # mysqlresults = ActiveRecord::Base.connection.execute(query)
    # mysqlresults.each(:as => :hash) do |row|
    #   album_stats['comment'][row['album_id'].to_s]=row['thecount']
    # end
    # query = "select album_id, count(*) as thecount from snap_likes group by 1"
    # mysqlresults = ActiveRecord::Base.connection.execute(query)
    # mysqlresults.each(:as => :hash) do |row|
    #   album_stats['like'][row['album_id'].to_s]=row['thecount']
    # end
    
    # Getting album 5 recent snaps list and recent participants list
    recent_image_urls = {}
    participants_array = []
    query = "select s.album_id, s.id, s.user_id, s.photo_file_name
              from albums a
              join snaps s on s.album_id = a.id
              where a.id in (#{album_id_string})
              order by a.updated_at desc, s.created_at desc"
    mysqlresults = ActiveRecord::Base.connection.execute(query)
    mysqlresults.each(:as => :hash) do |row|
        
      # Get participant list based on recent + 1st degree friends
      if (friend_id_array.has_key?(row['user_id'].to_s) || row['user_id'].to_i == @current_user.id) && participants_array.uniq.length<3
        
        # TODO: uniqify the string list of participants
        if row['user_id'].to_i == @current_user.id
          participants_array << "You"
        else
          participants_array << friend_id_array[row['user_id'].to_s]['name']
        end
      end
      
      if !recent_image_urls.has_key?(row['album_id'].to_s)
        recent_image_urls[row['album_id'].to_s] = []
      end
      # Get only 5 most recent pictures; original or thumbnail?
      if recent_image_urls[row['album_id'].to_s].length<5
        photo_url = row['photo_file_name']
        recent_image_urls[row['album_id'].to_s] << "#{S3_BASE_URL}/photos/#{row['id']}/original/#{row['photo_file_name']}"
      end
      
    end
    
    ###
    # Getting albums
    ###

    # Prepare Query
    query = "
      select
        a.id, a.last_snap_id, a.name, s.user_id, u.name as 'user_name', u.picture_url,
        s.message, s.media_type, s.photo_file_name, s.lat, s.lng, a.updated_at,
        sum(case when s.media_type='photo' then 1 else 0 end) as photo_count
      from albums a
      join snaps s on a.last_snap_id = s.id
      join users u on u.id = s.user_id
      where a.id in (#{album_id_string})
      group by 1
    "
    
    # Fetch Results
    # http://s3.amazonaws.com/kupo/kupos/photos/".$places[$key]['id']."/original/".$places[$key]['photo_file_name']
    # short square photo size; figure out how to pass this size later
    response_array = []
    mysqlresults = ActiveRecord::Base.connection.execute(query)
    mysqlresults.each(:as => :hash) do |row|
      
      participants_string = ""
      puts "This is the length " + participants_array.length.to_s
      if participants_array.uniq.length <= participants_hash[row['id'].to_s].length
        participants_string = participants_array.join(',')
      else
        participants_string = participants_array.join(',') + " and #{participants_hash[row['id'].to_s].length - participants_array.length} more"
      end
      
      # Each response hash consists of album id, name, and last_snap details flattened
      row_hash = {
        :id => row['id'].to_s, # album id
        :name => row['name'], # album name
        :photo_count => row['photo_count'], # count of photos in album
        :participants => participants_hash[row['id'].to_s], # list of participants for this album
        :participants_string => participants_string, # list of participants
        :recent_image_urls => recent_image_urls[row['id'].to_s], # array of 5 recent image urls for album
        :timestamp => row['updated_at'].to_i # album updated_at
      }
      response_array << row_hash
    end
    
    # :participant_list
        # participants_hash[row['album_id'].to_s]
    # :pregen_participant_string (up to 6 people and total count of first degree friends)
        # 3 ppl and 123 more (estimate 60 characters including the "and...")
        # make it dynamic so we can pass more ppl depending on client
        # second degree is always in the 'and more' section
        # list of ppl is sorted by first degree last update/add time
    
    # Paging
    paging_hash = {}
    # paging_hash[:since] = response_array.first[:timestamp].nil? ? Time.now.to_i : response_array.first[:timestamp]
    # paging_hash[:until] = response_array.last[:timestamp].nil? ? Time.now.to_i : response_array.first[:timestamp]
    
    # Construct Response
    @response_hash = {}
    @response_hash[:data] = response_array
    @response_hash[:paging] = paging_hash

    api_call_duration = Time.now.to_f - api_call_start
    LOGGING::Logging.logfunction(request,@current_user.id,'album#index',nil,nil,api_call_duration,nil,nil,nil)

    respond_to do |format|
      format.html # event/kupos.html.erb template
      format.xml  { render :xml => @response_hash }
      format.json  { render :json => @response_hash }
    end
  end

  # Create a new album along with the first snap associated to it
  # TODO construct FB post back to wall with tagged list
  # @param REQUIRED name
  # @param REQUIRED tagged (comma separated of user ids)
  # @param REQUIRED access_token
  # Authentication required
  def create
    self.authenticate_token

    Rails.logger.info request.query_parameters.inspect
    api_call_start = Time.now.to_f

    # Should we create the event tag on the server side? (probably)
    # tag = "#" + params[:name].gsub(/[^0-9A-Za-z]/, '')
    # tag.downcase!
    # tag_count = Event.count(:conditions => "tag LIKE '%#{tag}.%'")
    # tag = tag + ".#{tag_count + 1}"

    # Create the album
    album = Album.create(
      :name => params[:name]
    )
    
    # Create the snap
    if params[:snap_type]='video'
      params[:video]=params[:media]
    elsif params[:snap_type]='photo'
      params[:photo]=params[:media]
    else
    end
    s = Snap.create(
      :album_id => album.id,
      :media_type => params[:media_type],
      :user_id => @current_user.id,
      :photo => params[:photo],
      :video => params[:video],
      :message => params[:message]  
    )
    
    # Update the album with last snap_id
    album.update_attribute(:last_snap_id, s.id)
    
    # Update user last snap_id
    u = User.find_by_id(@current_user.id)
    u.update_attribute(:last_snap_id, s.id)

    response = {:success => "true"}

    api_call_duration = Time.now.to_f - api_call_start
    LOGGING::Logging.logfunction(request,@current_user.id,'album#create',nil,nil,api_call_duration,nil,nil,nil)

    respond_to do |format|
      format.xml  { render :xml => response }
      format.json  { render :json => response }
    end

  end


  ###
  ### OLD APIs, for more see the scrapboard repo
  ###

  # Show all kupos related to an event without using AR
  # http://localhost:3000/v1/kupos/16?access_token=17fa35a520ac7cc293c083680028b25198feb72033704f1a30bbc4298217065ed310c0d9efae7d05f55c9154601ab767511203e68f02610180ea3990b22ff991
  def kupos
    # logging(request, actiontype, lat=nil, lng=nil, var1=nil, var2=nil)
    Rails.logger.info request.query_parameters.inspect

    api_call_start = Time.now.to_f

    # We should limit results to 50 if no count is specified
    limit_count = "limit 50"
    if !params[:count].nil?
      limit_count = "limit "+params[:count].to_s
    end

    # Event filter
    event_condition = "event_id = #{params[:event_id]}"

    # Content filter = Video, photo, or video and photo only
    content_type_conditions = ""
    if params[:media_type].nil?
    elsif params[:media_type]=="video_only"
      content_type_conditions = " AND has_video=1"
    elsif params[:media_type]=="photo_only"
      # it's a photo only, not a photo snapshot of video
      content_type_conditions = " AND has_photo=1 AND has_video=0"
    else
      # video OR photo
      content_type_conditions = " AND has_photo+has_video>0"
    end

    query = "select k.*, u.facebook_id, u.name
              from kupos k
              join users u on k.user_id = u.id
            where " + event_condition + content_type_conditions + "
            order by k.created_at desc
            " + limit_count
    response_array = []
    mysqlresults = ActiveRecord::Base.connection.execute(query)
    mysqlresults.each(:as => :hash) do |k|
      row_hash = {
        :id => k['id'].to_s,
        :event_id => k['event_id'].to_s,
        :author_id => k['user_id'].to_s,
        :author_facebook_id => k['facebook_id'].to_s,
        :author_name => k['name'],
        :message => k['message'],
        :has_photo => k['has_photo'],
        :has_video => k['has_video'],
        :photo_file_name => k['photo_file_name'],
        :video_file_name => k['video_file_name'],
        :timestamp => k['updated_at'].to_i
      }
      response_array << row_hash
    end

    # Construct Response
    @response_hash = {}
    @response_hash[:data] = response_array

    api_call_duration = Time.now.to_f - api_call_start
    LOGGING::Logging.logfunction(request,nil,'event#kupos',nil,nil,api_call_duration,params[:event_id],nil,nil)

    respond_to do |format|
      format.html # event/kupos.html.erb template
      format.xml  { render :xml => @response_hash }
      format.json  { render :json => @response_hash }
    end
  end

  # Show all kupos related to an event
  def kupos_ar
    # logging(request, actiontype, lat=nil, lng=nil, var1=nil, var2=nil)
    Rails.logger.info request.query_parameters.inspect

    api_call_start = Time.now.to_f

    # We should limit results to 50 if no count is specified
    limit_count = 50
    if !params[:count].nil?
      limit_count = params[:count].to_i
    end

    # Video, photo, or video and photo only
    set_conditions = "event_id = #{params[:event_id]}"
    if params[:media_type].nil?
    elsif params[:media_type]=="video_only"
      set_conditions = "event_id = #{params[:event_id]} AND has_video=1"
    elsif params[:media_type]=="photo_only"
      # it's a photo only, not a photo snapshot of video
      set_conditions = "event_id = #{params[:event_id]} AND has_photo=1 AND has_video=0"
    else
      # video OR photo
      set_conditions = "event_id = #{params[:event_id]} AND has_photo+has_video>0"
    end

    kupos = Kupo.find(:all, :conditions => set_conditions, :order => 'created_at DESC', :limit => limit_count)

    response_array = []
    kupos.each do |k|
      row_hash = {
        :id => k.id.to_s,
        :event_id => k.event_id.to_s,
        :author_id => k.user.id.to_s,
        :author_facebook_id => k.user.facebook_id.to_s,
        :author_name => k.user.name,
        :message => k.message,
        :has_photo => k.has_photo,
        :has_video => k.has_video,
        :photo_file_name => k.photo_file_name,
        :video_file_name => k.video_file_name,
        :timestamp => k.updated_at.to_i
      }
      response_array << row_hash
    end

    # Construct Response
    @response_hash = {}
    @response_hash[:data] = response_array

    api_call_duration = Time.now.to_f - api_call_start
    LOGGING::Logging.logfunction(request,nil,'event#kupos',nil,nil,api_call_duration,params[:event_id],nil,nil)

    respond_to do |format|
      format.html
      format.xml  { render :xml => @response_hash }
      format.json  { render :json => @response_hash }
    end
  end

  def test
    test_response = %{
      {
        "data" : [
          {
            "id" : "1",
            "name" : "Poker Night 3",
            "user_id" : "1",
            "user_name" : "Peter Shih",
            "user_picture_url" : "https://graph.facebook.com/ptshih/picture",
            "message" : "Lost $20 in one hand...",
            "photo_url" : "http://a8.sphotos.ak.fbcdn.net/hphotos-ak-snc6/226475_1931611046467_1127993981_32240309_4949789_n.jpg",
            "type" : "photo",
            "photo_count" : "7",
            "like_count" : "3",
            "comment_count" : "2",
            "lat" : "37.7805",
            "lng" : "-122.4100",
            "timestamp" : 1300930808
          },
          {
            "id" : "2",
            "name" : "Girls Girls Girls!",
            "user_id" : "2",
            "user_name" : "James Liu",
            "user_picture_url" : "https://graph.facebook.com/ptshih/picture",
            "message" : "Look at them booty!",
            "photo_url" : "http://a8.sphotos.ak.fbcdn.net/hphotos-ak-snc6/226475_1931611046467_1127993981_32240309_4949789_n.jpg",
            "type" : "photo",
            "photo_count" : "7",
            "like_count" : "3",
            "comment_count" : "2",
            "lat" : "37.7815",
            "lng" : "-122.4101",
            "timestamp" : 1290150808
          },
          {
            "id" : "3",
            "name" : "Nice Cars, etc...",
            "user_id" : "3",
            "user_name" : "Nathan Bohannon",
            "user_picture_url" : "https://graph.facebook.com/ptshih/picture",
            "message" : "R8 in front of verde",
            "photo_url" : "http://a8.sphotos.ak.fbcdn.net/hphotos-ak-snc6/226475_1931611046467_1127993981_32240309_4949789_n.jpg",
            "type" : "photo",
            "photo_count" : "7",
            "like_count" : "3",
            "comment_count" : "2",
            "lat" : "37.7825",
            "lng" : "-122.4102",
            "timestamp" : 1290140802
          },
          {
            "id" : "4",
            "name" : "Verde Tea",
            "user_id" : "3",
            "user_name" : "Thomas Liou",
            "user_picture_url" : "https://graph.facebook.com/ptshih/picture",
            "message" : "Hotties!",
            "photo_url" : "http://a8.sphotos.ak.fbcdn.net/hphotos-ak-snc6/226475_1931611046467_1127993981_32240309_4949789_n.jpg",
            "type" : "photo",
            "photo_count" : "7",
            "like_count" : "3",
            "comment_count" : "2",
            "lat" : "37.7825",
            "lng" : "-122.4102",
            "timestamp" : 1290130802
          }
        ],
        "paging" : {
          "since" : 1300930808,
          "until" : 1290130802
        }
      }
    }

    render :json => test_response
    return
  end
end
