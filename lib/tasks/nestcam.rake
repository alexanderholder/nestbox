require "net/http"
require "uri"
require "json"
require "openssl"

namespace :Nestbox do
  desc "Show Pub/Sub setup instructions for real-time events"
  task pubsub_setup: :environment do
    project_id = Rails.application.credentials.dig(:nest, :project_id)

    puts <<~INSTRUCTIONS
      Pub/Sub Setup for Real-Time Events
      ===================================

      STEP 1: Create Pub/Sub Topic
      ----------------------------
      1. Go to: https://console.cloud.google.com/cloudpubsub/topic/list
      2. Click "Create Topic"
      3. Topic ID: nestbox-events
      4. Uncheck "Add a default subscription"
      5. Click Create

      STEP 2: Grant Nest Permission to Publish
      ----------------------------------------
      1. Click on your new topic (nestbox-events)
      2. Go to "Permissions" tab
      3. Click "Add Principal"
      4. Principal: sdm-service@sdm-prod.iam.gserviceaccount.com
      5. Role: Pub/Sub Publisher
      6. Save

      STEP 3: Add Topic to Device Access Console
      ------------------------------------------
      1. Go to: https://console.nest.google.com/device-access/project/#{project_id}
      2. Click "Edit" next to Pub/Sub topic
      3. Enter: projects/YOUR_GCP_PROJECT_ID/topics/nestbox-events
      4. Save

      STEP 4: Create Pull Subscription
      --------------------------------
      1. Go to: https://console.cloud.google.com/cloudpubsub/subscription/list
      2. Click "Create Subscription"
      3. Subscription ID: nestbox-events-sub
      4. Select topic: nestbox-events
      5. Delivery type: Pull
      6. Acknowledgement deadline: 60 seconds
      7. Click Create

      STEP 5: Create Service Account for Rails
      ----------------------------------------
      1. Go to: https://console.cloud.google.com/iam-admin/serviceaccounts
      2. Click "Create Service Account"
      3. Name: nestbox-app
      4. Grant role: Pub/Sub Subscriber
      5. Click "Create Key" > JSON
      6. Save the JSON file

      STEP 6: Add Credentials to Rails
      --------------------------------
      Save the JSON key file to: config/google_cloud_credentials.json

      Or set environment variable:
        export GOOGLE_APPLICATION_CREDENTIALS=/path/to/credentials.json

      STEP 7: Add Gem to Gemfile
      --------------------------
      gem "google-cloud-pubsub"

      Then run: bundle install

      STEP 8: Test Events
      -------------------
        rails nestbox:poll_events

    INSTRUCTIONS
  end

  desc "Poll Pub/Sub for events (one-time check)"
  task poll_events: :environment do
    require "google/cloud/pubsub"

    gcp_project = ENV["GOOGLE_CLOUD_PROJECT"] || Rails.application.credentials.dig(:google_cloud, :project_id)
    subscription_name = ENV["PUBSUB_SUBSCRIPTION"] || "nestbox-events-sub"

    if gcp_project.blank?
      puts "ERROR: Set GOOGLE_CLOUD_PROJECT env var or google_cloud.project_id in credentials"
      exit 1
    end

    puts "Connecting to Pub/Sub..."
    pubsub = Google::Cloud::PubSub.new(project_id: gcp_project)

    puts "Getting subscription: #{subscription_name}"
    subscriber = pubsub.subscriber(subscription_name)

    puts "Polling for messages..."
    messages = subscriber.pull(max: 10, immediate: true)

    if messages.empty?
      puts "No new events"
    else
      puts "Received #{messages.count} event(s):"
      messages.each do |message|
        data = JSON.parse(message.data)
        puts
        puts "  Event ID: #{data.dig("resourceUpdate", "events")&.keys&.first}"
        puts "  Device: #{data.dig("resourceUpdate", "name")&.split("/")&.last}"
        puts "  Timestamp: #{data["timestamp"]}"
        puts "  Data: #{data.dig("resourceUpdate", "events")}"

        message.acknowledge!
      end
    end
  rescue Google::Cloud::NotFoundError => e
    puts "ERROR: Subscription not found"
    puts "Run 'rails nestbox:pubsub_setup' for setup instructions"
    exit 1
  rescue => e
    puts "ERROR: #{e.class}: #{e.message}"
    puts "Make sure you've completed the Pub/Sub setup (rails nestbox:pubsub_setup)"
    exit 1
  end

  desc "Show setup instructions"
  task setup_instructions: :environment do
    puts <<~INSTRUCTIONS
      Nestbox Setup - Google Device Access API
      =========================================

      STEP 1: Register for Device Access ($5 one-time fee)
      ----------------------------------------------------
      1. Go to: https://console.nest.google.com/device-access
      2. Accept Terms of Service and pay $5
      3. Note your "Project ID" after creation

      STEP 2: Create Google Cloud Project
      ------------------------------------
      1. Go to: https://console.cloud.google.com
      2. Create a new project (or use existing)
      3. Enable "Smart Device Management API":
         - APIs & Services > Enable APIs > Search "Smart Device Management"
         - Click Enable

      STEP 3: Create OAuth2 Credentials
      ---------------------------------
      1. Go to: APIs & Services > Credentials
      2. Create Credentials > OAuth Client ID
      3. Application type: "Web application"
      4. Authorized redirect URIs: http://localhost:3000/oauth/callback
      5. Note your Client ID and Client Secret

      STEP 4: Configure OAuth Consent Screen
      --------------------------------------
      1. Go to: APIs & Services > OAuth consent screen
      2. User type: External
      3. Add your email as a test user
      4. Add scope: https://www.googleapis.com/auth/sdm.service

      STEP 5: Link Your Nest Account
      ------------------------------
      Run this task to get the authorization URL:

        rails nestbox:authorize

      STEP 6: Add Credentials
      -----------------------
      rails credentials:edit

        nest:
          project_id: your-device-access-project-id
          client_id: your-oauth-client-id.apps.googleusercontent.com
          client_secret: your-oauth-client-secret
          refresh_token: (will be added after authorization)

      STEP 7: Test Connection
      -----------------------
        rails nestbox:test_connection

    INSTRUCTIONS
  end

  desc "Generate OAuth authorization URL"
  task authorize: :environment do
    client_id = Rails.application.credentials.dig(:nest, :client_id)
    project_id = Rails.application.credentials.dig(:nest, :project_id)

    if client_id.blank? || project_id.blank?
      puts "ERROR: Missing nest.client_id or nest.project_id in credentials"
      puts "Run 'rails nestbox:setup_instructions' for setup guide"
      exit 1
    end

    redirect_uri = "http://localhost:3000/oauth/callback"
    scope = "https://www.googleapis.com/auth/sdm.service"

    auth_url = "https://nestservices.google.com/partnerconnections/#{project_id}/auth?" + URI.encode_www_form(
      redirect_uri: redirect_uri,
      access_type: "offline",
      prompt: "consent",
      client_id: client_id,
      response_type: "code",
      scope: scope
    )

    puts "Open this URL in your browser to authorize Nestbox:"
    puts
    puts auth_url
    puts
    puts "After authorizing, you'll be redirected to a URL like:"
    puts "  http://localhost:3000/oauth/callback?code=XXXX&scope=..."
    puts
    puts "Copy the 'code' parameter and run:"
    puts "  rails 'Nestbox:exchange_token[YOUR_CODE_HERE]'"
  end

  desc "Exchange authorization code for tokens"
  task :exchange_token, [ :code ] => :environment do |t, args|
    code = args[:code]
    if code.blank?
      puts "Usage: rails 'Nestbox:exchange_token[YOUR_AUTH_CODE]'"
      exit 1
    end

    client_id = Rails.application.credentials.dig(:nest, :client_id)
    client_secret = Rails.application.credentials.dig(:nest, :client_secret)
    redirect_uri = "http://localhost:3000/oauth/callback"

    uri = URI("https://www.googleapis.com/oauth2/v4/token")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    store = OpenSSL::X509::Store.new
    store.set_default_paths
    store.flags = 0
    http.cert_store = store

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/x-www-form-urlencoded"
    request.body = URI.encode_www_form(
      client_id: client_id,
      client_secret: client_secret,
      code: code,
      grant_type: "authorization_code",
      redirect_uri: redirect_uri
    )

    response = http.request(request)
    data = JSON.parse(response.body)

    if data["error"]
      puts "ERROR: #{data["error"]} - #{data["error_description"]}"
      exit 1
    end

    puts "SUCCESS! Add this to your credentials (rails credentials:edit):"
    puts
    puts "nest:"
    puts "  refresh_token: #{data["refresh_token"]}"
    puts
    puts "Access token (expires in #{data["expires_in"]}s): #{data["access_token"][0..50]}..."
  end

  desc "Test Nest API connection"
  task test_connection: :environment do
    puts "Testing Nest API connection..."

    connection = NestConnectionStatus.current
    cameras = connection.fetch_cameras

    puts "Connection successful!"
    puts "Found #{cameras.length} camera(s):"
    cameras.each do |camera|
      puts "  - #{camera[:name]}"
      puts "    Type: #{camera[:device_type]}"
      puts "    ID: #{camera[:id]}"
      puts
    end
  rescue NestConnectionStatus::Api::AuthenticationError => e
    puts "Authentication failed: #{e.message}"
    puts ""
    puts "Run 'rails nestbox:setup_instructions' for setup guide."
    exit 1
  rescue NestConnectionStatus::Api::ApiError => e
    puts "API error: #{e.message}"
    exit 1
  end

  desc "Setup cameras from Nest API"
  task setup: :environment do
    puts "Fetching cameras from Nest..."

    Camera.refresh_from_nest.each do |camera|
      puts "  - #{camera.name} (#{camera.device_type})"
    end

    puts "Setup complete! #{Camera.count} camera(s) configured."
  rescue NestConnectionStatus::Api::AuthenticationError => e
    puts "Authentication failed: #{e.message}"
    exit 1
  end

  desc "Sync all cameras now"
  task sync: :environment do
    puts "Syncing all cameras..."

    Camera.find_each do |camera|
      print "  - #{camera.name}..."
      camera.sync_now
      puts " #{camera.events.count} events"
    rescue => e
      puts " ERROR: #{e.message}"
    end

    puts "Sync complete!"
  end

  desc "Download pending event clips"
  task download: :environment do
    pending = Event.pending_download.count
    puts "Downloading #{pending} pending clip(s)..."

    Event.pending_download.find_each do |event|
      print "  - #{event.nest_id}..."
      event.download_now
      puts " done"
    rescue => e
      puts " ERROR: #{e.message}"
    end

    puts "Download complete!"
  end

  desc "Retry failed downloads"
  task retry_failed: :environment do
    failed = Event.failed_download.count
    puts "Retrying #{failed} failed download(s)..."

    Event.retry_all_failed

    puts "Retry jobs enqueued!"
  end

  desc "Show status"
  task status: :environment do
    status = NestConnectionStatus.current

    puts "Nestbox Status"
    puts "=" * 40
    puts "Connection: #{status.state}"
    puts "Last success: #{status.last_success_at || 'Never'}"
    puts "Last failure: #{status.last_failure_at || 'Never'}"
    puts "Last error: #{status.last_error || 'None'}" if status.last_error
    puts ""
    puts "Cameras: #{Camera.count}"
    puts "Events:"
    puts "  - Total: #{Event.count}"
    puts "  - Pending download: #{Event.pending_download.count}"
    puts "  - Downloaded: #{Event.downloaded.count}"
    puts "  - Failed: #{Event.failed_download.count}"
  end
end
