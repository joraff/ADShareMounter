#!/usr/bin/env ruby

require 'rubygems'
require 'json'
require 'uri'
require 'logger'
require File.expand_path(File.dirname(__FILE__) + '/ad_adapters')

# Get current logged in user
CURRENT_USER = `id -un`.strip

# Get computer name
# TODO: move this into the adapter to get the name we're actually bound as. Can be different from the computer name
COMPUTER_NAME = `scutil --get ComputerName`.strip


# Log level
LOG = Logger.new(STDOUT)
LOG.level = Logger::INFO


#####################

def main
  ADAdapters.adapter = select_default_adapter  
  groups = ADAdapters.get_groups(CURRENT_USER, "user")
  
  unless groups.nil? || groups.empty?
    shares = find_shares_in_groups(groups)
    shares.each do |share|
      share.mount if share.is_a? Share
    end
  else
    LOG.warn "No group membership was found for object: #{CURRENT_USER}"
  end
  
  
  # If multiple shares were mounted, their desktop icons sometimes will overlap each other. Tell Finder to cleanup to arrange these.
  `osascript -e 'tell application "Finder" to clean up window of desktop by name'`
end

def find_shares_in_groups(groups)
  shares = []
  
  if groups.empty?
    LOG.warn "Warning: no group members found in #{ALL_SHARES_GROUP}"
  else
    groups.each do |group|
      data = ADAdapters.get_info(group)
      if data.nil? || data.empty?
        LOG.warn "Warning: group '#{group}' has an empty info attribute"
      else
        begin
          json_segments = data.extract_json
          
          json_segments.each do |data|
            obj = JSON.parse(data)
            if ! obj.is_a? Hash
              LOG.warn "JSON object from #{group} does not convert to a hash"
            elsif ! obj.has_key? "shares"
              LOG.warn "JSON object from #{group} doesn't contain a shares key"
            else
              case obj["shares"]
              when Array
                obj["shares"].each do |share|
                  LOG.debug "Our shares was an array"
                  LOG.debug "Processing share data: #{share.inspect}"                  
                  shares << Share.new(share)
                end
              else # Hash or String
                unless obj["shares"].empty?
                  LOG.debug "Creating new share object with arg: #{obj["shares"].inspect}"
                  shares << Share.new(obj["shares"]) 
                end
              end
            end
          end # end json_sengments loop
        rescue JSON::ParserError => e
          LOG.warn "Warning: group '#{group}' has a json error: #{e}"
        end # end trap
      end
    end
  end
  shares
end

def get_shares
  shares = []
  
  groups = ADAdapters.enum_groups
  
  if groups.empty?
    LOG.warn "Warning: no group members found in #{ALL_SHARES_GROUP}"
  else
    groups.each do |group|
      data = ADAdapters.get_info(group)
      if data.empty?
        LOG.warn "Warning: group '#{group}' has an empty info attribute"
      else
        begin
          json_segments = data.extract_json
          
          json_segments.each do |data|
            obj = JSON.parse(data)
            if ! obj.is_a? Hash
              LOG.warn "JSON object from #{group} does not convert to a hash"
            elsif ! obj.has_key? "shares"
              LOG.warn "JSON object from #{group} doesn't contain a shares key"
            else
              case obj["shares"]
              when Array
                obj["shares"].each do |share|
                  LOG.debug "Our shares was an array"
                  LOG.debug "Processing share data: #{share.inspect}"
                  member_type = (share.has_key? "member_type") ? share['member_type'] : 'user'
                  result = ADAdapters.check_membership(group, member_type)
                  LOG.debug "Result from membership check: #{result}"
                  
                  if result
                    shares << Share.new(share)
                  else
                    LOG.debug "#{member_type} was not found to be a member of #{group}. Skipping share."
                  end
                end
              else
                unless obj["shares"].empty?
                  LOG.debug "Creating new share object with arg: #{obj["shares"].inspect}"
                  member_type = (obj["shares"].has_key? "member_type") ? obj["shares"]['member_type'] : 'user'
                  result = ADAdapters.check_membership(group, member_type)
                  LOG.debug "Result from membership check: #{result}"
                  if result
                    shares << Share.new(obj["shares"]) 
                  else
                    LOG.debug "#{member_type} was not found to be a member of #{group}. Skipping share."
                  end
                end
              end
            end
          end
        rescue JSON::ParserError => e
          LOG.warn "Warning: group '#{group}' has a json error: #{e}"
        end
      end
    end
  end
  shares
end





class String  
  def occurances_of(str, offset=0)
    occ = []
    index = 0
    begin
      index = self.index("}", offset+index+1)
      occ << index unless index.nil?
    end while index != nil
    occ
  end
  
  def extract_json
    json_segments = []

    begin
      offset = 0 unless offset
      first_open = self.index("{", offset)

      all_close = self.occurances_of('}', offset)
      all_close.each do |end_pos|
        begin
          obj = JSON.parse(self[first_open..end_pos])
        rescue JSON::ParserError
        else
          offset = end_pos
          json_segments << self[first_open..end_pos]
          break
        end
      end
    end while !all_close.empty?
    json_segments
  end
end

class Share
  def initialize(arg)
    
    @user = `id -un`.strip
    
    case arg
    when Hash
      
      if arg.has_key? 'domain'
        @domain = arg['domain']
        LOG.debug "set local domain variable = #{arg['domain']}"
      end
      if arg.has_key? 'path'
        @share = arg['path'] 
        LOG.debug "set local share variable = #{arg['path']}"
        @uri = URI.parse expand_variables(@share)
      else
        LOG.warn "Path key is required for a share"
        return
      end
      
      @mountname = (arg.has_key? 'mountname') ? arg['mountname'] : @uri.path.split("/").last
      LOG.debug "set mountname variable = #{@mountname}"
      
    when String
      @share = arg
      @uri = URI.parse(@share)
    end
    
  end
  
  def mount
    user = `id -un`.strip
    
    LOG.debug "Username we're using to mount with is #{user}"
        
    mountpoint = "/Volumes/#{mountname}"
    `mkdir -p "#{mountpoint}"`
    `chmod 777 "#{mountpoint}"`
    LOG.info "Mountpoint created at #{mountpoint}"
    
    sharestring = "//\""
    sharestring << "#{@domain};" if @domain
    sharestring << "#{user}\""
    sharestring << "@\"#{@uri.host}#{sharepath}\""
    
    result = `mount_smbfs #{sharestring} "#{mountpoint}" 2>&1`
    if $? != 0
      LOG.error "Unable to mount #{sharestring} at #{mountpoint}: #{result}"
    else
      LOG.info "#{mountname} successfully mounted."
    end
  end

  def mountname
    expand_variables @mountname
  end
  
  def sharepath
    expand_variables @uri.path
  end
  
  private
  
  def expand_variables(str)
    # Expand username variable %U
    if str.include? "%U"
      str.gsub!("%U", @user)
    end
    str
  end
end

def select_default_adapter
  # Assume that if the pbis tools are installed, we should use pbis
  if File.exist? "/opt/pbis"
    :pbis
  else
    :ds
  end
end

main