# Usage: $ ruby sauce_monitor.rb sgrove.tst tchapman.rks adifranco.col jchou.hip sarahmc.aus

require 'rubygems'
require 'sauce'

class SauceMonitor
  attr_accessor :client, :domain_names

  def initialize(options={})
    puts "Started with #{options.inspect}"
    @client = Sauce::Client.new(:username => options[:username],
                                :access_key => options[:access_key],
                                :ip => options[:ip])
    
    @domain_names = options[:domain_names]
    puts "Watching these tunnels: #{domain_names}"
  end

  def repair_tunnel(tunnel)
    puts "Tunnel named #{tunnel.domain_names} (#{tunnel}) is hurt."
    repaired = tunnel.mini_repair
    return tunnel if repaired

    puts "Tunnel named #{tunnel.domain_names} is dead. Repairing..."
    tunnel.destroy
    puts "\tdetroyed. sleep for 5s"
    sleep 5

    new_tunnel = @client.tunnels.create("DomainNames" => tunnel.domain_names)
    new_tunnel.refresh!
    STDOUT.print "\tWaiting for new machine to boot"

    until new_tunnel.status == "running"
      new_tunnel.refresh!
      STDOUT.print "."; STDOUT.flush
      sleep 5
    end
    puts "Booted. Sleeping 15s for ssh to start on tunnel machine"
    
    sleep 15
    new_tunnel.open_gateway
    puts "\t Gateway opened"
    return new_tunnel
  end

  def monitor
    create_tunnels

    # By now all the tunnels have been created (but maybe not booted)
    tunnels = @client.tunnels.all.select { |tunnel| @domain_names.include? tunnel.domain_names.first }

    while true
      tunnels.each_with_index do |tunnel, index|
        puts "#{index}.) Checking #{tunnel.domain_names} (#{tunnel}) [#{tunnel.status}]..."
        tunnel.refresh!
        if tunnel.preparing? or tunnel.halting? # It's cool, just wait. Relax man.
          puts "#{tunnel.domain_names} (#{tunnel}) still booting"
        else
          if not tunnel.healthy? # If it's not booting, we expect it to be healthy
            new_tunnel = repair_tunnel(tunnel) 
            puts "New tunnel: #{new_tunnel}"
            tunnels.delete_at index
            tunnels << new_tunnel
          end
        end
        puts "Finished checking #{tunnel.domain_names} (#{tunnel})..."
      end
 
      puts "--" * 40

      sleep 10
    end
  end

  protected

  def create_tunnels
    domain_names.each { |domain_name| create_tunnel(domain_name) }
  end

  def create_tunnel(domain_name)
    tunnels = @client.tunnels.all
    if tunnels.select { |tunnel| tunnel.domain_names == [domain_name] }.empty? # If this domain isn't in the current tunnels, create it
      puts "DomainName #{domain_name} not found in current tunnels, creating"
      @client.tunnels.create("DomainNames" => [domain_name])
    end
  end
end

account = YAML.load("live_account.yml")
monitor = SauceMonitor.new(:domain_names => ARGV,
                           :username => account["username"],
                           :password => account["password"],
                           :ip => account["ip"])
monitor.monitor
