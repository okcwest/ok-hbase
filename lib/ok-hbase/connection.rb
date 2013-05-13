require 'thrift'
require 'thrift/transport/socket'
require 'thrift/protocol/binary_protocol'

require 'thrift/hbase/hbase_constants'
require 'thrift/hbase/hbase_types'
require 'thrift/hbase/hbase'

module OkHbase
  class Connection


    DEFAULT_OPTS = {
        host: 'localhost',
        port: 9090,
        timeout: 5,
        auto_connect: false,
        table_prefix: nil,
        table_prefix_separator: '_',
        transport: :buffered
    }.freeze

    THRIFT_TRANSPORTS = {
        buffered: Thrift::BufferedTransport,
        framed: Thrift::FramedTransport,
    }

    attr_accessor :host, :port, :timeout, :auto_connect, :table_prefix, :table_prefix_separator
    attr_reader :client

    def initialize(opts={})
      opts = DEFAULT_OPTS.merge opts

      raise ArgumentError.new ":transport must be one of: #{THRIFT_TRANSPORTS.keys}" unless THRIFT_TRANSPORTS.keys.include?(opts[:transport])
      raise TypeError.new ":table_prefix must be a string" unless defined?(opts[:table_prefix]) && !opts[:table_prefix].is_a?(String)
      raise TypeError.new ":table_prefix_separator must be a string" unless opts[:table_prefix_separator].is_a?(String)


      @host = opts[:host]
      @port = opts[:port]
      @timeout = opts[:timeout]
      @auto_connect = opts[:auto_connect]
      @table_prefix = opts[:table_prefix]
      @table_prefix_separator = opts[:table_prefix_separator]
      @transport_class = THRIFT_TRANSPORTS[opts[:transport]]

      _refresh_thrift_client
      open if @auto_connect

    end

    def open
      return if open?
      @transport.open

      OkHbase.logger.info "OkHbase connected"
    end

    def open?
      @transport && @transport.open?
    end

    def close
      return unless open?
      @transport.close
    end

    def table(name, use_prefix=true)
      name = _table_name(name) if use_prefix
      OkHbase::Table.new(name, self)
    end

    def tables
      names = @client.getTableNames
      names = names.map { |n| n[table_prefix.size...-1] if n.start_with?(table_prefix) } if table_prefix
      names
    end

    def create_table(name, families)
      name = _table_name(name)

      raise ArgumentError.new "Can't create table #{name}. (no column families specified)" unless families
      raise TypeError.new "families' arg must be a hash" unless families.respond_to?(:[])

      column_descriptors = []

      families.each_pair do |family_name, options|
        options ||= {}

        args = {}
        options.each_pair do |option_name, value|
          args[option_name.camelcase(:lower)] = value
        end

        family_name = "#{family_name}:" unless family_name.to_s.end_with? ':'
        args[:name] = family_name

        column_descriptors << Apache::Hadoop::Hbase::Thrift::ColumnDescriptor.new(args)
      end

      client.createTable(name, column_descriptors)
    end

    def delete_table(name, disable=false)
      name = _table_name(name)

      disable_table(name) if disable && table_enabled?(name)
      client.deleteTable(name)
    end

    def enable_table(name)
      name = _table_name(name)

      client.enableTable(name)
    end

    def disable_table(name)
      name = _table_name(name)

      client.disableTable(name)
    end

    def table_enabled?(name)
      name = _table_name(name)

      return client.isTableEnabled(name)
    end

    private

    def _refresh_thrift_client
      socket = Thrift::Socket.new(host, port, timeout)
      @transport = @transport_class.new(socket)
      protocol = Thrift::BinaryProtocolAccelerated.new(@transport)
      @client = Apache::Hadoop::Hbase::Thrift::Hbase::Client.new(protocol)

    end

    def _table_name(name)
      table_prefix && !name.start_with?(table_prefix) ? [table_prefix, name].join(table_prefix_separator) : name
    end
  end
end