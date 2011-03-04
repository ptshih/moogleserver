Moogle::Application.routes.draw do
  
  # Routes will always pass a version
  # Example: http://api.moogle.com/v1/user/54685403
  
  # Moogle Routes
  match ':version/moogle/register', :controller => 'moogle', :action => 'register', :via => :post # Register new user
  match ':version/moogle/session', :controller => 'moogle', :action => 'session', :via => :post # Start session for user
  
  match ':version/moogle/kupos', :controller => 'moogle', :action => 'kupos', :via => :get # Kupos API; referral activity stream
  match ':version/moogle/me', :controller => 'moogle', :action => 'me', :via => :get # ME profile
  
  # User Routes
  match ':version/users', :controller => 'user', :action => 'index', :via => :get # List of Users
  match ':version/users/:id', :controller => 'user', :action => 'show', :via => :get # Single User with ID
  
  # Checkin Routes
  match ':version/checkins/checkin', :controller => 'checkin', :action => 'checkin', :via => :post # User checked in to a place
  match ':version/checkins', :controller => 'checkin', :action => 'index', :via => :get # List of Checkins, with filters
  
  # Place routes
  # match ':version/place', :controller => 'place', :action => 'index', :via => :get # List of Places
  match ':version/places/share', :controller => 'place', :action => 'share', :via => :post # User shared a place
  match ':version/places/nearby', :controller => 'place', :action => 'nearby', :via => :get # get nearby facebook places
  match ':version/places/popular', :controller => 'place', :action => 'popular', :via => :get # Get popular places visited by friends
  match ':version/places/shared', :controller => 'place', :action => 'shared', :via => :get # Get places shared by friends
  match ':version/places/followed', :controller => 'place', :action => 'followed', :via => :get # Get places followed
  match ':version/places/:place_id', :controller => 'place', :action => 'show', :via => :get # get a single place's default info
  match ':version/places/:place_id/activity', :controller => 'place', :action => 'activity', :via => :get # get single place's friend's activity
  match ':version/places/:place_id/feed', :controller => 'place', :action => 'feed', :via => :get # place's posts
  match ':version/places/:place_id/reviews', :controller => 'place', :action => 'reviews', :via => :get # place's reviews
  match ':version/places/:place_id/topvisitors', :controller => 'place', :action => 'topvisitors', :via => :get # place's reviews
  
  # Mobile Server Examples  
  # map.connect ':version/messages/count', :controller => 'messages', :action => 'count', :conditions => { :method => :get }
    
  # The priority is based upon order of creation:
  # first created -> highest priority.

  # Sample of regular route:
  #   match 'products/:id' => 'catalog#view'
  # Keep in mind you can assign values other than :controller and :action

  # Sample of named route:
  #   match 'products/:id/purchase' => 'catalog#purchase', :as => :purchase
  # This route can be invoked with purchase_url(:id => product.id)

  # Sample resource route (maps HTTP verbs to controller actions automatically):
  #   resources :products

  # Sample resource route with options:
  #   resources :products do
  #     member do
  #       get 'short'
  #       post 'toggle'
  #     end
  #
  #     collection do
  #       get 'sold'
  #     end
  #   end

  # Sample resource route with sub-resources:
  #   resources :products do
  #     resources :comments, :sales
  #     resource :seller
  #   end

  # Sample resource route with more complex sub-resources
  #   resources :products do
  #     resources :comments
  #     resources :sales do
  #       get 'recent', :on => :collection
  #     end
  #   end

  # Sample resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end

  # You can have the root of your site routed with "root"
  # just remember to delete public/index.html.
  # root :to => "welcome#index"

  # See how all your routes lay out with "rake routes"

  # This is a legacy wild controller route that's not recommended for RESTful applications.
  # Note: This route will make all actions in every controller accessible via GET requests.
  # match ':controller(/:action(/:id(.:format)))'
end
