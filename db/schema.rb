# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 20110202082319) do

  create_table "apps", :force => true do |t|
    t.integer  "app_id",     :limit => 8, :default => 0
    t.string   "name"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "checkins", :force => true do |t|
    t.integer  "checkin_id",      :limit => 8, :default => 0
    t.integer  "facebook_id",     :limit => 8, :default => 0
    t.integer  "place_id",        :limit => 8, :default => 0
    t.integer  "app_id",  :limit => 8, :default => 0
    t.string   "message"
    t.datetime "created_time"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "checkins_users", :force => true do |t|
    t.integer  "checkin_id",  :limit => 8, :default => 0
    t.integer  "facebook_id", :limit => 8, :default => 0
  end

  create_table "gowallas", :force => true do |t|
    t.integer  "gowalla_id",     :limit => 8,                                 :default => 0
    t.integer  "place_id",       :limit => 8,                                 :default => 0
    t.string   "name"
    t.integer  "checkins_count"
    t.decimal  "lat",                 :precision => 20, :scale => 16
    t.decimal  "lng",                 :precision => 20, :scale => 16
    t.string   "raw_hash" # this stores the parsed json, raw hash from gowalla, in case we need to parse stuff out of it later
    t.datetime "expires_at" # this tells the scraper when it should rescrape the place
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "places", :force => true do |t|
    t.integer  "place_id",   :limit => 8,                                 :default => 0
    t.integer  "yelp_id",    :limit => 8,                                 :default => 0
    t.integer  "gowalla_id", :limit => 8,                                 :default => 0
    t.string   "name"
    t.decimal  "lat",               :precision => 20, :scale => 16
    t.decimal  "lng",               :precision => 20, :scale => 16
    t.string   "street"
    t.string   "city"
    t.string   "state"
    t.string   "country"
    t.string   "zip"
    t.string   "raw_hash" # this stores the parsed json, raw hash from facebook, in case we need to parse stuff out of it later
    t.datetime "expires_at" # this tells the scraper when it should rescrape the place
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "users", :force => true do |t|
    t.integer  "facebook_id",    :limit => 8, :default => 0
    t.integer  "third_party_id", :limit => 8, :default => 0
    t.string   "access_token"
    t.string   "full_name"
    t.string   "first_name"
    t.string   "last_name"
    t.string   "gender"
    t.datetime  "last_fetched_checkins" # store datetime of last time checkins were fetched from facebook
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "yelp", :force => true do |t|
    t.string  "yelp_id"
    t.integer  "place_id",     :limit => 8,                                 :default => 0
    t.string   "name"
    t.string   "phone"
    t.integer  "review_count"
    t.decimal  "lat",                  :precision => 20, :scale => 16
    t.decimal  "lng",                  :precision => 20, :scale => 16
    t.string   "raw_hash" # this stores the parsed json, raw hash from yelp, in case we need to parse stuff out of it later
    t.datetime "expires_at" # this tells the scraper when it should rescrape the place
    t.datetime "created_at"
    t.datetime "updated_at"
  end
  
  create_table "yelp_reviews", :force => true do |t|
    t.string "yelp_review_id" 
    t.integer "yelp_id",      :limit  => 8, :default => 0
    t.string  "excerpt"
    t.integer "rating",       :limit  => 1, :default => 0
    t.datetime  "time_created"
    t.string  "user_name"
    t.string  "user_id"
    t.string  "raw_hash"
    t.datetime "created_at"
    t.datetime "updated_at"  
  end

  

end
