$:.unshift File.dirname(__FILE__)
require 'freshbooks/extensions'
require 'freshtrack/core_ext'
require 'yaml'

module Freshtrack
  class << self
    attr_reader :config, :project_name, :project, :task
    
    def init(project = nil)
      load_config
      @project_name = project
      FreshBooks.setup("#{company}.freshbooks.com", token)
    end
    
    def load_config
      @config = YAML.load(File.read(File.expand_path('~/.freshtrack.yml')))
    end
    
    def company
      project_info_value('company')
    end
    
    def token
      project_info_value('token')
    end
    
    def project_info_value(key)
      return config[key.to_s] unless project_name
      info = project_task_mapping[project_name]
      return config[key.to_s] unless info[:company] and info[:token]
      info[key.to_sym]
    end
    private :project_info_value
    
    def project_task_mapping
      config['project_task_mapping']
    end
    
    def get_project_data(project_name)
      raise "Could not find a mapping for project named `#{project_name}`" unless mapping = project_task_mapping[project_name]
      @project = FreshBooks::Project.find_by_name(mapping[:project])
      raise "Could not locate a FreshBooks project called `#{mapping[:project]}`" unless @project
      @task = FreshBooks::Task.find_by_name(mapping[:task])
      raise "Could not locate a FreshBooks task called `#{mapping[:task]}`" unless @task
    end
    
    def get_data(project_name, options = {})
      get_project_data(project_name)
      collector(options).get_time_data(project_name)
    end
    
    def track(project_name, options = {})
      data = get_data(project_name, options)
      tracked = get_tracked_data(data)
      data.each do |entry_data|
        tracked_entry = tracked.detect { |t|  t.date == entry_data['date'] }
        create_entry(entry_data, tracked_entry)
      end
    end

    def get_tracked_data(data)
      return [] if data.empty?
      dates = data.collect { |d|  d['date'] }
      FreshBooks::TimeEntry.list('project_id' => project.project_id, 'task_id' => task.task_id, 'date_from' => dates.min, 'date_to' => dates.max)
    end

    def create_entry(entry_data, time_entry = FreshBooks::TimeEntry.new)
      time_entry ||= FreshBooks::TimeEntry.new

      time_entry.project_id = project.project_id
      time_entry.task_id    = task.task_id
      time_entry.date       = entry_data['date']
      time_entry.hours      = entry_data['hours']
      time_entry.notes      = entry_data['notes']

      method = time_entry.time_entry_id ? :update : :create
      result = time_entry.send(method)

      if result
        true
      else
        STDERR.puts "warning: unsuccessful time entry creation for date #{entry_data['date']}"
        nil
      end
    end
    
    def collector(options = {})
      collector_name = config['collector']
      class_name = collector_name.capitalize.gsub(/([a-z])_([a-z])/) { "#{$1}#{$2.upcase}" }
      require "freshtrack/time_collectors/#{collector_name}"
      klass = Freshtrack::TimeCollector.const_get(class_name)
      klass.new(options)
    end
    
    def open_invoices
      invoices = FreshBooks::Invoice.list || []
      invoices.select { |i|  i.open? }
    end
    
    def invoice_aging
      open_invoices.collect do |i|
        {
          :id     => i.invoice_id,
          :number => i.number,
          :client => i.client.organization,
          :age    => Date.today - i.date,
          :status => i.status,
          :amount => i.amount,
          :owed   => i.owed_amount
        }
      end
    end

    def unbilled_time(project_name)
      time_entries = get_unbilled_time_entries(project_name)
      time_entries.collect(&:hours).inject(&:+)
    end

    def get_unbilled_time_entries(project_name)
      get_project_data(project_name)
      time_entries = FreshBooks::TimeEntry.list('project_id' => @project.project_id, 'per_page' => 100)
      time_entries.reject(&:billed)
    end
  end
end
