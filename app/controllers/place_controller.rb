#require 'yelp_scraper'

class PlaceController < ApplicationController
  before_filter :default_geocoordinates
  before_filter do |controller|
    # This will set the @version variable
    controller.load_version(["v1","v2","v3"])
    controller.authenticate_token # sets the @current_user var based on passed in access_token (FB)
  end
  
  ###
  ### Convenience Methods
  ###
  
  def yelpScrape
    if params[:url]
      url = url.gsub('http://www.yelp.com','')
      render:text => YelpScraper.new.extractTermsForYelpBiz(url).to_json
    end
  end

  ###
  ### API Endpoints
  ###

  # feed: the posts/comments feed of a particular place
  # show: the information about a place - address, lat/lng, likes, checkins etc.
  # activity: activity stream of checkins by your friends
  # top_visiting_friends: top list of friends who have visited this place

  def index
    
    
    
  end
  
  ############################################################  
  # Returns general information of this place
  # params[:place_id]
  # TODO Add nearby places which are also popular
  ############################################################
  def show
    Rails.logger.info request.query_parameters.inspect
   
    # Gets number of friend checkins at this place
    facebook_id_array = Friend.select('friend_id').where("facebook_id = #{@current_user.facebook_id}").map {|f| f.friend_id}
    people_list = facebook_id_array.join(",")
    #     query = "checkins.place_id = #{params[:place_id]} and tagged_users.facebook_id in (#{people_list})"
    #     friend_checkins = Checkin.find(:all, :conditions=> query, :include=>:tagged_users, :joins=>"join tagged_users on tagged_users.checkin_id = checkins.checkin_id").count
    friend_checkins = TaggedUser.find(:all, :conditions=>"place_id = #{params[:place_id]} and facebook_id in (#{people_list})").count

    # Gets the place
    place = Place.find(:all, :conditions=> "place_id = #{params[:place_id]}").first
    
    # Gets top 5 nearby places within #{distance} miles
    top_places = []
    total_score = 0
    distance_in_mi = 5
    distance_col = "(3956.0 * 2.0 * atan2( power(power(sin((lat - #{place['lat']}) * pi()/180.0),2) + cos(#{place['lat']} * pi()/180.0) * cos(lat * pi()/180.0) * power(sin((lng - #{place['lng']}) * pi()/180.0),2), 0.5), power( 1.0 - power(sin((lat - #{place['lat']}) * pi()/180.0),2) + cos(#{place['lat']} * pi()/180.0) * cos(lat * pi()/180.0) * power(sin((lng - #{place['lng']}) * pi()/180.0),2) , 0.5) ))"
    query = "select p.*, count(*) as friend_checkins, count(*)*100 + p.like_count*10 + p.checkin_count as score, "+distance_col+" as distance
        from tagged_users a
        right join places p on p.place_id = a.place_id and p.place_id != #{params[:place_id]}
        where a.facebook_id in (select friend_id from friends where facebook_id = #{@current_user.facebook_id}) 
        and " + distance_col + " < " + distance_in_mi.to_s+ "
        group by 1,2,3,4
        order by score desc limit 5"
    mysqlresults = ActiveRecord::Base.connection.execute(query)
    while loop_top_place = mysqlresults.fetch_hash do
      top_places_hash ={
        :place_id => loop_top_place['place_id'].to_s,
        :place_name => loop_top_place['name'],
        :place_picture => loop_top_place['picture'],
        :place_friend_checkins => friend_checkins,
        :place_likes => loop_top_place['like_count'],
        :place_checkins => loop_top_place['checkin_count'],
        :place_distance => loop_top_place['distance'],
        :score => loop_top_place['score']
      }
      total_score += loop_top_place['score'].to_i
      top_places << top_places_hash
    end
    # Converting score to percentage
    top_places.each do |top_place|
      top_place[:score] = (top_place[:score].to_f/total_score.to_f*100).round
    end
    
    
    # Gets Yelp, OPTIMIZE LATER
    if place.yelp.nil?
      place.scrape_yelp
    end
    yelp = Yelp.find_by_place_id(place['place_id'])
    
    # Calculate the distance between params[:lat] params[:lng] and place.lat place.lng
    d2r = Math::PI/180.0
    dlong = (place.lng.to_f - params[:lng].to_f) * d2r;
    dlat = (place.lat.to_f - params[:lat].to_f) * d2r;
    a = (Math.sin(dlat/2.0))**2.0 + Math.cos(params[:lat].to_f*d2r) * Math.cos(place.lat.to_f*d2r) * (Math.sin(dlong/2.0))**2.0;
    c = 2.0 * Math.atan2(a**(1.0/2.0), (1.0-a)**(1.0/2.0));
    distance = 3956.0 * c;
    
    # /place/place_id
    response_hash = {
      :place_id => place['place_id'].to_s,
      :place_name => place['name'],
      :place_picture => place['picture'],
      :place_lng => place['lng'],
      :place_lat => place['lat'],
      :place_street => place['street'],
      :place_city => place['city'],
      :place_state => place['state'],
      :place_country => place['country'],
      :place_zip => place['zip'],
      :place_phone => place['phone'],
      :place_checkins => place['checkin_count'],
      :place_distance => distance,
      :place_friend_checkins => friend_checkins,
      :place_likes => place['like_count'],
      :place_attire => place['attire'],
      :place_website => place['website'],
      :place_price => place['price_range'],
      :place_reviews => yelp.nil? ? 0 : yelp.review_count,
      :place_rating => yelp.nil? ? "0 star rating" : yelp.rating,
      :place_terms => yelp.nil? ? nil : yelp.yelp_terms.map {|t| t.term }.join(', '),
      :place_categories => yelp.nil? ? nil : yelp.yelp_categories.map {|c| c.category }.join(', '),
      :top_places_nearby => top_places
    }
    
    #puts response_array.to_json
    
    respond_to do |format|
      format.xml  { render :xml => response_hash }
      format.json  { render :json => response_hash }
    end

  end
  
  def search
  end

  ############################################################
  # Show nearby places
  # params[:lat], params[:lng]
  # facebook API returns a filtered by distance list; so we don't have to filter in SQL DB
  ############################################################
  def nearby
    Rails.logger.info request.query_parameters.inspect
    api_call_start = Time.now.to_f
    #puts "lol: #{params}"
    
    # PLACE filter
    # default distance filter set to 1km
    filter_distance = 1000
    puts "this is the distance passed now"+params[:distance].to_s
    if params[:distance]!=nil
      # convert distance to meters; client calls API with miles filter
      filter_distance = (params[:distance].to_i * 1609.3440).round
    end
    puts "filter distiance "+ filter_distance.to_s
    
    place_id_array = @facebook_api.find_places_near_location(params[:lat], params[:lng], filter_distance, nil)
    place_list = place_id_array.join(',')
    
    # Adds pages to all the new places
    # NOTE: DISABLE TEMPORARILY
    # @facebook_api.find_page_for_page_alias(place_id_array)
    
    # LIMIT 
    limit_count = " limit 100"
    if !params[:limit].nil?
      limit_count = " limit #{params[:limit]}"
    end
    
    # ORDER
    # Returns the result by order of distance, ascending
    order_statement = "3956.0 * 2.0 * atan2( power(power(sin((lat - #{params[:lat]}) * pi()/180.0),2) + cos(#{params[:lat]} * pi()/180.0) * cos(lat * pi()/180.0) * power(sin((lng - #{params[:lng]}) * pi()/180.0),2), 0.5), power( 1.0 - power(sin((lat - #{params[:lat]}) * pi()/180.0),2) + cos(#{params[:lat]} * pi()/180.0) * cos(lat * pi()/180.0) * power(sin((lng - #{params[:lng]}) * pi()/180.0),2) , 0.5) )"
    
    # DISTANCE
    if params[:distance].nil?
      params[:distance]=1
    end
    if params[:distance]!=nil && params[:lng]!=nil && params[:lat]!=nil
      distance_filter = " or (3956.0 * 2.0 * atan2( power(power(sin((lat - #{params[:lat]}) * pi()/180.0),2) + cos(#{params[:lat]} * pi()/180.0) * cos(lat * pi()/180.0) * power(sin((lng - #{params[:lng]}) * pi()/180.0),2), 0.5), power( 1.0 - power(sin((lat - #{params[:lat]}) * pi()/180.0),2) + cos(#{params[:lat]} * pi()/180.0) * cos(lat * pi()/180.0) * power(sin((lng - #{params[:lng]}) * pi()/180.0),2) , 0.5) )) <= #{params[:distance]}"
    end
    
    query = "
      select a.*, sum(case when b.facebook_id is not null then 1 else 0 end) as friend_checkins
      from places a
      left join tagged_users b on a.place_id = b.place_id
        and (b.facebook_id in (select friend_id from friends where facebook_id=#{@current_user.facebook_id})
            or b.facebook_id=#{@current_user.facebook_id})
      where a.place_id IN (#{place_list})" + distance_filter + "
      group by 1
      order by " + order_statement + limit_count
    
    response_array = []
    mysqlresults = ActiveRecord::Base.connection.execute(query)
    mysqlresults.each(:as => :hash) do |row|
      # calculate the distance between params[:lat] params[:lng] and place.lat place.lng
      d2r = Math::PI/180.0
      dlong = (row['lng'].to_f - params[:lng].to_f) * d2r;
      dlat = (row['lat'].to_f - params[:lat].to_f) * d2r;
      a = (Math.sin(dlat/2.0))**2.0 + Math.cos(params[:lat].to_f*d2r) * Math.cos(row['lat'].to_f*d2r) * (Math.sin(dlong/2.0))**2.0;
      c = 2.0 * Math.atan2(a**(1.0/2.0), (1.0-a)**(1.0/2.0));
      distance = 3956.0 * c;
            
      row_hash = {
        :place_id => row['place_id'].to_s,
        :place_name => row['name'],
        :place_picture => row['picture'],
        :place_lng => row['lng'],
        :place_lat => row['lat'],
        :place_street => row['street'],
        :place_city => row['city'],
        :place_state => row['state'],
        :place_country => row['country'],
        :place_zip => row['zip'],
        :place_phone => row['phone'],
        :place_checkins => row['checkin_count'],
        :place_distance => distance,
        :place_friend_checkins => row['friend_checkins'],
        :place_likes => row['like_count']
      }
      response_array << row_hash
    end
    
    api_call_duration = Time.now.to_f - api_call_start
    LOGGING::Logging.logfunction(request,@current_user.facebook_id,'nearby',params[:lat], params[:lng],api_call_duration,nil) 
    
    # Construct Response
    response_hash = {}
    response_hash[:values] = response_array
    response_hash[:count] = response_array.length
    response_hash[:total] = response_array.length
     
    respond_to do |format|
      format.xml  { render :xml => response_hash }
      format.json  { render :json => response_hash }
    end
  end
  
  ############################################################
  # Show checkin trends; sort descending popularity
  # Popularity can be sorted by params[:sort] = "like_count", "checkin_count", "friend_checkins"
  # Also can be filtered by distance by params[:distance] = 1 (this is in miles)
  # Also can exclude places you have been params[:exclude_places_you_been] = "true" (1 is true, 0 is false)
  # Also can limit response params[:limit] = 10
  ############################################################
  def popular
    Rails.logger.info request.query_parameters.inspect
    #puts "passed params: #{params}"
    
    exclude_places_you_been = ""
    if params[:exclude].to_s == "true"
      exclude_places_you_been = " and a.place_id not in (select place_id from tagged_users where facebook_id = #{@current_user.facebook_id})" 
    end
    
    filter_limit = 25
    if !params[:limit].nil?
      filter_limit = params[:limit].to_i
    end
    
    filter_random = ""
    
    if params[:random]==nil || params[:random]=="false"
      filter_random = ""
    else
      #filter_random = ", rand()"
      filter_limit = filter_limit * 5
    end
    
    if params[:sort].nil?
      params[:sort] = "friend_checkins"
    end
    
    distance_filter = ""
    if params[:distance]!=nil && params[:lng]!=nil && params[:lat]!=nil
      distance_filter = " and (3956.0 * 2.0 * atan2( power(power(sin((lat - #{params[:lat]}) * pi()/180.0),2) + cos(#{params[:lat]} * pi()/180.0) * cos(lat * pi()/180.0) * power(sin((lng - #{params[:lng]}) * pi()/180.0),2), 0.5), power( 1.0 - power(sin((lat - #{params[:lat]}) * pi()/180.0),2) + cos(#{params[:lat]} * pi()/180.0) * cos(lat * pi()/180.0) * power(sin((lng - #{params[:lng]}) * pi()/180.0),2) , 0.5) )) <= #{params[:distance]}"
    end
    
    query = "select p.*, count(*) as friend_checkins
        from tagged_users a
        join places p on p.place_id = a.place_id
        where a.facebook_id in (select friend_id from friends where facebook_id = #{@current_user.facebook_id}) 
        " + distance_filter + "
        " + exclude_places_you_been + "
        group by 1,2,3,4
        order by #{params[:sort]} desc " + filter_random + "
        limit " + filter_limit.to_s
    mysqlresults = ActiveRecord::Base.connection.execute(query)
    response_array = []
    mysqlresult_iterator = mysqlresults.num_rows
    mysqlresults.each(:as => :hash) do |row|
      # mysqlresult_iterator -= 1
      d2r = Math::PI/180.0
      dlong = (place['lng'].to_f - params[:lng].to_f) * d2r;
      dlat = (place['lat'].to_f - params[:lat].to_f) * d2r;
      a = (Math.sin(dlat/2.0))**2.0 + Math.cos(params[:lat].to_f*d2r) * Math.cos(place['lat'].to_f*d2r) * (Math.sin(dlong/2.0))**2.0;
      c = 2.0 * Math.atan2(a**(1.0/2.0), (1.0-a)**(1.0/2.0));
      distance = 3956.0 * c;

      # /place/place_id
      row_hash = {
        :place_id => place['place_id'].to_s,
        :place_name => place['name'],
        :place_picture => place['picture'],
        :place_lng => place['lng'],
        :place_lat => place['lat'],
        :place_street => place['street'],
        :place_city => place['city'],
        :place_state => place['state'],
        :place_country => place['country'],
        :place_zip => place['zip'],
        :place_phone => place['phone'],
        :place_checkins => place['checkin_count'],
        :place_distance => distance,
        :place_friend_checkins => place['friend_checkins'],
        :place_likes => place['like_count'],
        :place_attire => place['attire'],
        :place_website => place['website'],
        :place_price => place['price_range']
      }
      
      #(mysqlresults.num_rows-response_array.length)
      #(mysqlresult_iterator - response_array.length)
      # if response_array.length < params[:limit].to_i && rand(( (mysqlresult_iterator - response_array.length)/params[:limit].to_i).round)==0
      #         response_array << response_hash         
      #       end
      response_array << row_hash

    end
    
    
    # Return first few elements up to amount params[:limit]
    if params[:random]=="true"
      response_array = response_array.sort_by{rand}[0..(filter_limit/5)-1.to_i]
    end
    
    # Construct Response
    response_hash = {}
    response_hash[:values] = response_array
    response_hash[:count] = response_array.length
    response_hash[:total] = response_array.length
    
    respond_to do |format|
      format.xml  { render :xml => response_array }
      format.json  { render :json => response_array }
    end
  end
  
  
  ###
  ### Place Endpoints for a Single Place
  ###
  
  def kupos
    # logging(request, actiontype, lat=nil, lng=nil, var1=nil, var2=nil)
    Rails.logger.info request.query_parameters.inspect
    
    api_call_start = Time.now.to_f
    
    # We should limit results to 50 if no count is specified
     limit_count = 50
     if !params[:count].nil?
       limit_count = params[:count].to_i
     end
    
     ##
     # Getting tagged user of a place grouped by checkin_id
     ##
     friend_list_of_place = {}
     query = "select a.checkin_id, b.facebook_id, b.name
         from checkins a
         join tagged_users b on a.checkin_id = b.checkin_id and a.facebook_id != b.facebook_id
         where a.place_id = #{params[:place_id]} and a.facebook_id in
            (select friend_id from friends where facebook_id = #{@current_user.facebook_id})"
         
     # join friends f on b.facebook_id = f.friend_id or a.facebook_id= #{@current_user.facebook_id}
     mysqlresults = ActiveRecord::Base.connection.execute(query)
     mysqlresults.each(:as => :hash) do |row|
       if !friend_list_of_place.has_key?(row['checkin_id'].to_s)
         friend_list_of_place[row['checkin_id'].to_s] = []
         friend_hash = {
           :facebook_id => row['facebook_id'],
           :full_name => row['name'],
           :first_name => row['name']
         }
         friend_list_of_place[row['checkin_id'].to_s] << friend_hash
       else
         friend_hash = {
           :facebook_id => row['facebook_id'],
           :full_name => row['name'],
           :first_name => row['name']
         }
         friend_list_of_place[row['checkin_id'].to_s] << friend_hash
       end      
     end
    
     # convert the UTC unix timestamp to Ruby Date and them back to MySQL datetime (utc)
     # retarded lol
    # pass since, then get everything > since
    if params[:since]!=nil && params[:until]==nil
      since_time = Time.at(params[:since].to_i).utc.to_s(:db)
      time_bounds = " and kupos.created_at > ('#{since_time}')"
    # pass until, then get everything < until
    elsif params[:since]==nil && params[:until]!=nil
      until_time = Time.at(params[:until].to_i).utc.to_s(:db)
      time_bounds = " and kupos.created_at < ('#{until_time}')"
    else
      time_bounds = ""
    end
    
    query = " select a.id, a.facebook_id, a.place_id, a.checkin_id, a.app_name, a.kupo_type, a.comment, a.has_photo, a.has_video, a.photo_file_name, a.video_file_name, a.created_at, b.full_name
    from kupos a
    join users b on a.facebook_id = b.facebook_id
    where (a.facebook_id in (select friend_id from friends where facebook_id=#{@current_user.facebook_id})
        or a.facebook_id=#{@current_user.facebook_id})
        and a.place_id = #{params[:place_id]}
        " + time_bounds + "
    order by id desc
    "
    response_hash = {}
    response_array = []
    total_count=0
    mysqlresults = ActiveRecord::Base.connection.execute(query)
    mysqlresults.each(:as => :hash) do |row|
      
      limit_count-=1
      total_count+=1
      if limit_count>=0
        if !row['checkin_id'].nil?
          friend_list = friend_list_of_place[row['checkin_id'].to_s]
        end
        row_hash = {
          :id => row['id'].to_s,
          :place_id => row['place_id'].to_s,
          :author_id => row['facebook_id'].to_s,
          :author_name => row['full_name'],
          :app_name => row['app_name'],
          :kupo_type => row['kupo_type'],
          :friend_list => friend_list,
          :comment => row['comment'],
          :has_photo => row['has_photo'],
          :has_video => row['has_video'],
          :photo_file_name => row['photo_file_name'],
          :video_file_name => row['video_file_name'],
          :timestamp => row['created_at'].to_i
        }
        response_array << row_hash
        
      end
    end
    
    # Construct Response
    response_hash[:values] = response_array
    response_hash[:count] = response_array.length
    response_hash[:total] = total_count
    
    api_call_duration = Time.now.to_f - api_call_start
    LOGGING::Logging.logfunction(request,@current_user.facebook_id,'kupos',nil,nil,api_call_duration,params[:place_id],response_hash[:total],response_hash[:count])
    
    respond_to do |format|
      format.xml  { render :xml => response_hash }
      format.json  { render :json => response_hash }
    end
  
  end
  
  
  # Exact same call as 'kupos' except with the filter
  # 'a.photo_file_name is not null'
  # In the future may not need to grab tagged user information... unless they are viewing the
  # enlarged photo itself; in album view it may not be necessary
  def photos
    Rails.logger.info request.query_parameters.inspect
    
    api_call_start = Time.now.to_f
    
    # We should limit results to 50 if no count is specified
     limit_count = 50
     if !params[:count].nil?
       limit_count = params[:count].to_i
     end
    
     ##
     # Getting tagged user of a place grouped by checkin_id
     ##
     friend_list_of_place = {}
     query = "select a.checkin_id, b.facebook_id, b.name
         from checkins a
         join tagged_users b on a.checkin_id = b.checkin_id and a.facebook_id != b.facebook_id
         where a.place_id = #{params[:place_id]} and a.facebook_id = #{@current_user.facebook_id}"
         
     # join friends f on b.facebook_id = f.friend_id or a.facebook_id= #{@current_user.facebook_id}
     mysqlresults = ActiveRecord::Base.connection.execute(query)
     mysqlresults.each(:as => :hash) do |row|
       if !friend_list_of_place.has_key?(row['checkin_id'].to_s)
         friend_list_of_place[row['checkin_id'].to_s] = []
         friend_hash = {
           :facebook_id => row['facebook_id'],
           :full_name => row['name'],
           :first_name => row['name']
         }
         friend_list_of_place[row['checkin_id'].to_s] << friend_hash
       else
         friend_hash = {
           :facebook_id => row['facebook_id'],
           :full_name => row['name'],
           :first_name => row['name']
         }
         friend_list_of_place[row['checkin_id'].to_s] << friend_hash
       end      
     end
    
     # convert the UTC unix timestamp to Ruby Date and them back to MySQL datetime (utc)
     # retarded lol
    # pass since, then get everything > since
    if params[:since]!=nil && params[:until]==nil
      since_time = Time.at(params[:since].to_i).utc.to_s(:db)
      time_bounds = " and kupos.created_at > ('#{since_time}')"
    # pass until, then get everything < until
    elsif params[:since]==nil && params[:until]!=nil
      until_time = Time.at(params[:until].to_i).utc.to_s(:db)
      time_bounds = " and kupos.created_at < ('#{until_time}')"
    else
      time_bounds = ""
    end
    
    query = " select a.id, a.facebook_id, a.place_id, a.checkin_id, a.kupo_type, a.comment, a.has_photo, a.has_video, a.created_at, b.full_name
    from kupos a
    join users b on a.facebook_id = b.facebook_id
    where (a.facebook_id in (select friend_id from friends where facebook_id=#{@current_user.facebook_id})
        or a.facebook_id=#{@current_user.facebook_id})
        and a.place_id = #{params[:place_id]}
        and a.photo_file_name is not null
        " + time_bounds + "
    order by id desc
    "
    response_hash = {}
    response_array = []
    total_count=0
    mysqlresults = ActiveRecord::Base.connection.execute(query)
    mysqlresults.each(:as => :hash) do |row|
      
      limit_count-=1
      total_count+=1
      if limit_count>=0
        if !row['checkin_id'].nil?
          friend_list = friend_list_of_place[row['checkin_id'].to_s]
        end
        row_hash = {
          :id => row['id'].to_s,
          :place_id => row['place_id'].to_s,
          :author_id => row['facebook_id'].to_s,
          :author_name => row['full_name'],
          :kupo_type => row['kupo_type'],
          :friend_list => friend_list,
          :comment => row['comment'],
          :has_photo => row['has_photo'],
          :has_video => row['has_video'],
          :timestamp => row['created_at'].to_i
        }
        response_array << row_hash
        
      end
    end
    
    # Construct Response
    response_hash[:values] = response_array
    response_hash[:count] = response_array.length
    response_hash[:total] = total_count
    
    api_call_duration = Time.now.to_f - api_call_start
    LOGGING::Logging.logfunction(request,@current_user.facebook_id,'photos',
        nil,nil,api_call_duration,params[:place_id],response_hash[:total],response_hash[:count])
    
    respond_to do |format|
      format.xml  { render :xml => response_hash }
      format.json  { render :json => response_hash }
    end
   
  end
  
  ############################################################
  # Place Yelp Reviews
  ############################################################
  def reviews
    
    response_array = []
    
    place = Place.find_by_place_id(params[:place_id])
    
    if !place.yelp.nil?
      reviews_array = place.yelp.yelp_reviews
    end
    
    if !reviews_array.nil?
      reviews_array.each do |r|
        review_hash = {
          :yelp_pid => r.yelp_pid,
          :rating => r.rating,
          :text => r.text
        }
        response_array << review_hash
      end
    end
    
    respond_to do |format|
      format.xml  { render :xml => response_array }
      format.json  { render :json => response_array }
    end
  end

  ############################################################
  # Returns sorted timeline of friend's activity at this location
  ############################################################
  def activity
    Rails.logger.info request.query_parameters.inspect

    # @current_user.facebook_id
    # params[:place_id]
    
    if params[:limit].nil?
      limit_return = 50
    else
      limit_return = params[:limit]
    end
    
    facebook_id_array = Friend.select('friend_id').where("facebook_id = #{@current_user.facebook_id}").map {|f| f.friend_id}
    facebook_id_array << @current_user.facebook_id
    people_list = facebook_id_array.join(",")
    query = "checkins.place_id=#{params[:place_id]} AND (tagged_users.facebook_id IN (#{people_list}))"
    
    response_array = []
    
    Checkin.find(:all, :select=>"tagged_users.name, tagged_users.facebook_id, checkins.created_time, checkins.checkin_id, checkins.message", :conditions=> query, :include=>:tagged_users, :joins=>"join tagged_users on tagged_users.checkin_id = checkins.checkin_id", :order => 'checkins.created_time DESC', :limit => limit_return).each do |taggeduser|
      response_hash = {
        :facebook_id => taggeduser['facebook_id'].to_s,
        :message => taggeduser['message'],
        :place_name => taggeduser['name'],
        :timestamp => taggeduser['created_time'].to_i
      }
      response_array << response_hash
    end
    
    respond_to do |format|
      format.xml  { render :xml => response_array }
      format.json  { render :json => response_array }
    end
    
  end
  
  ############################################################
  # Top visiting friends of this particular location
  # top_visiting_friends(place_id)
  ############################################################
  def topvisitors
    Rails.logger.info request.query_parameters.inspect
    
    query = "select a.facebook_id as friend_facebook_id, a.name as friend_name, count(*) as checkins
            from tagged_users a
            join checkins b on a.checkin_id = b.checkin_id and b.place_id = #{params[:place_id]}
            join places p on p.place_id = b.place_id
            where a.facebook_id = #{@current_user.facebook_id}
              or a.facebook_id in (select friend_id from friends where facebook_id = #{@current_user.facebook_id})
            group by 1,2
            order by 3 desc, 2"
    
    mysqlresults = ActiveRecord::Base.connection.execute(query)
    response_array = []
    rank = 0
    while mysqlresult = mysqlresults.fetch_hash do
      rank += 1
      refer_hash = {
        :rank => rank,
        :friend_facebook_id => mysqlresult['friend_facebook_id'],
        :friend_name => mysqlresult['friend_name'],
        :checkin_count => mysqlresult['checkin_count']
      }
      response_array << refer_hash
    end
    mysqlresults.free
    
    respond_to do |format|
      format.xml  { render :xml => response_array }
      format.json  { render :json => response_array }
    end

  end
  
end
