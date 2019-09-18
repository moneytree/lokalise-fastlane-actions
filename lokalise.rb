module Fastlane
  module Actions
    class LokaliseAction < Action
      def self.run(params)
        require 'net/http'

        token = params[:api_token]
        project_identifier = params[:project_identifier]
        destination = params[:destination]
        clean_destination = params[:clean_destination]
        include_comments = params[:include_comments] ? 1 : 0
        use_original = params[:use_original] ? 1 : 0

        request_data = {
          api_token: token,
          id: project_identifier,
          type: 'strings',
          use_original: use_original,
          bundle_filename: 'Localization.zip',
          bundle_structure: '%LANG_ISO%.lproj/Localizable.%FORMAT%',
          ota_plugin_bundle: 0,
          export_empty: 'base',
          include_comments: include_comments
        }

        languages = params[:languages]
        if languages.kind_of? Array
          request_data['langs'] = languages.to_json
        end

        request_data.merge!(params[:opts]) unless params[:opts].nil? || !params[:opts].kind_of?(Hash)
        UI.message "Exporting localizations with parameters #{request_data} 📦"

        tags = params[:tags]
        if tags.kind_of? Array then
          request_data["include_tags"] = tags.to_json
        end

        uri = URI('https://api.lokalise.com/api/project/export')
        request = Net::HTTP::Post.new(uri)
        request.set_form_data(request_data)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        response = http.request(request)

        json_response = JSON.parse(response.body)
        UI.error "Bad response 🉐\n#{response.body}" unless json_response.kind_of? Hash
        if json_response['response']['status'] == 'success' && json_response['bundle']['file'].kind_of?(String)
          UI.message 'Downloading localizations archive 📦'
          FileUtils.mkdir_p('lokalisetmp')
          file_path = json_response['bundle']['file']
          uri = URI("https://s3-eu-west-1.amazonaws.com/lokalise-assets/#{file_path}")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true

          zip_request = Net::HTTP::Get.new(uri)
          response = http.request(zip_request)
          if response.content_type == 'application/zip' || response.content_type == 'application/octet-stream'
            FileUtils.mkdir_p('lokalisetmp')
            open('lokalisetmp/a.zip', 'wb') {|file|
              file.write(response.body)
            }
            unzip_file('lokalisetmp/a.zip', destination, clean_destination)
            FileUtils.remove_dir('lokalisetmp')
            UI.success "Localizations extracted to #{destination} 📗 📕 📘"

            destination
          else
            UI.error 'Response did not include ZIP'
          end
        elsif json_response['response']['status'] == 'error'
          code = json_response['response']['code']
          message = json_response['response']['message']
          UI.error "Response error code #{code} (#{message}) 📟"
        else
          UI.error "Bad response 🉐\n#{json_response}"
        end
      end


      def self.unzip_file(file, destination, clean_destination)
        require 'zip'
        require 'rubygems'
        Zip::File.open(file) {|zip_file|
          if clean_destination
            UI.message 'Cleaning destination folder ♻️'
            FileUtils.remove_dir(destination)
            FileUtils.mkdir_p(destination)
          end
          UI.message 'Unarchiving localizations to destination 📚'
          zip_file.each {|f|
            f_path= File.join(destination, f.name)
            FileUtils.mkdir_p(File.dirname(f_path))
            FileUtils.rm(f_path) if File.file? f_path
            zip_file.extract(f, f_path)
          }
        }
      end


      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Download Lokalise localization'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :api_token,
                                       env_name: 'LOKALISE_API_TOKEN',
                                       description: 'API Token for Lokalise',
                                       verify_block: proc do |value|
                                         UI.user_error! "No API token for Lokalise given, pass using `api_token: 'token'`" unless (value and not value.empty?)
                                       end),

          FastlaneCore::ConfigItem.new(key: :project_identifier,
                                       env_name: 'LOKALISE_PROJECT_ID',
                                       description: 'Lokalise Project ID',
                                       verify_block: proc do |value|
                                         UI.user_error! "No Project Identifier for Lokalise given, pass using `project_identifier: 'identifier'`" unless (value and not value.empty?)
                                       end),

          FastlaneCore::ConfigItem.new(key: :destination,
                                       description: 'Localization destination',
                                       verify_block: proc do |value|
                                         UI.user_error! 'Destination is required' unless (value and not value.empty?)
                                         UI.user_error! 'Directory you passed is in your imagination' unless File.directory?(value)
                                       end),

          FastlaneCore::ConfigItem.new(key: :clean_destination,
                                       description: 'Clean destination folder',
                                       optional: true,
                                       is_string: false,
                                       default_value: false,
                                       verify_block: proc do |value|
                                         UI.user_error! 'Clean destination should be true or false' unless [true, false].include? value
                                       end),

          FastlaneCore::ConfigItem.new(key: :languages,
                                       description: 'Languages to download',
                                       optional: true,
                                       is_string: false,
                                       verify_block: proc do |value|
                                         UI.user_error! "Language codes should be passed as array" unless value.kind_of? Array
                                       end),

          FastlaneCore::ConfigItem.new(key: :include_comments,
                                       description: 'Include comments in exported files',
                                       optional: true,
                                       is_string: false,
                                       default_value: false,
                                       verify_block: proc do |value|
                                         UI.user_error! 'Include comments should be true or false' unless [true, false].include? value
                                       end),

          FastlaneCore::ConfigItem.new(key: :use_original,
                                       description: 'Use original filenames/formats (bundle_structure parameter is ignored then)',
                                       optional: true,
                                       is_string: false,
                                       default_value: false,
                                       verify_block: proc do |value|
                                         UI.user_error! 'Use original should be true of false.' unless [true, false].include?(value)
                                       end),

          FastlaneCore::ConfigItem.new(key: :tags,
                             description: "Include only the keys tagged with a given set of tags",
                             optional: true,
                             is_string: false,
                             verify_block: proc do |value|
                             UI.user_error! "Tags should be passed as array" unless value.kind_of? Array
                             end),

          FastlaneCore::ConfigItem.new(key: :opts,
                                       description: 'Additional parameters',
                                       optional: true,
                                       is_string: false,
                                       default_value: false,
                                       verify_block: proc do |value|
                                         UI.user_error! 'Additional parameters has to be Hash' if value && !value.kind_of?(Hash)
                                       end)
        ]
      end

      def self.authors
        'Fedya-L'
      end

      def self.is_supported?(platform)
        [:ios, :mac].include? platform
      end
    end
  end
end
