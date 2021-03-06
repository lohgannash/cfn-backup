require 'thor'
require 'fileutils'
require 'cfnbackup/log'
require 'cfnbackup/utils'
require 'cfnbackup/cfhighlander'

module CfnBackup
  class Generate < Thor::Group
    include Thor::Actions
    include Thor::Shell
    include CfnBackup::Log
    
    class_option :profile, aliases: :p, desc: 'AWS Profile'
    class_option :region, aliases: :r, default: ENV['AWS_REGION'], desc: 'AWS Region'
    class_option :verbose, desc: 'Enable DEBUG logging', type: :boolean
    
    class_option :config, desc: 'Provide a path to a config file to override defaults' # Optional
    class_option :stack_name, desc: 'Override the default stack name for the AWS Backup stack' # Optional
    
    def self.source_root
      File.dirname(__FILE__)
    end

    def set_loglevel
      Log.logger.level = Logger::DEBUG if @options['verbose']
      Log.logger.debug("Log level set to DEBUG")
    end

    # Sets the stack name to be used in template name & resource names. Defaults to cfnbackup if none provided
    def set_stack_name
      if @options['stack_name']
        @stack_name = @options['stack_name']
        Log.logger.debug("Stack name provided, set to #{@stack_name}")
      else
        @stack_name = "cfnbackup"
        Log.logger.debug("Using default stack name #{@stack_name}")
      end
    end

    # Creates the build dir based on the stack name
    def create_build_directory
      @build_dir = "output/#{@stack_name}"
      Log.logger.debug("Creating output directory #{@build_dir}")
      FileUtils.mkdir_p(@build_dir)
    end

    def initialize_config
      Log.logger.debug("Initialising config, loading global config file")
      # Load the global config file (should always be present in the hardcoded path)
      global_config_path = File.join(File.dirname(__FILE__), '../config/global_config.yml')
      global_config = YAML.load(File.read(global_config_path))
      # Check if a custom config file has been provided with the --config flag
      if @options['config']
        Log.logger.debug("Custom config file path provided, attempting to load")
        # Check if the file/path provided is a valid file and attempt to load it using the YAML object.
        if File.file?(@options['config'])
          custom_config = YAML.load(File.read(@options['config']))
          Log.logger.debug("Custom config file loaded, deep merging with global config")
          # Peform a deep merge on the loaded global config and the custom config
          @config = CfnBackup::Utils.deep_merge(global_config, custom_config)
        else
          abort("Could not find or load file #{@options['config']}")
        end
      else
        # If no custom config was provided no further action is needed
        Log.logger.debug("No custom config file provided, using all default values")
        @config = global_config
      end
      @config['stack_name'] = @stack_name
    end

    def generate_cloudformation
      Log.logger.debug("Populating CfHighlander file from template")
      # Inject the initalised config list into the text template which will use these to populate parameters
      template('templates/cfnbackup.cfhighlander.rb.tt', "#{@build_dir}/#{@stack_name}.cfhighlander.rb", @config, force: true)
      Log.logger.debug("Generating CloudFormation template from #{@build_dir}/#{@stack_name}.cfhighlander.rb")
      # Initalise the CfHighlander object and run a render, this will compile and validate the component, outputting cloudformation
      cfhl = CfnBackup::CfHighlander.new(@options['region'], @stack_name, @config, @build_dir)
      template_path = cfhl.render()
      Log.logger.debug("CloudFormation template generated and validated")
    end
  
  end

end