#!/usr/bin/env ruby

require 'rubygems'
require 'json'
require 'uri'
require 'logger'

# Define which group to enumerate for all the share groups
ALL_SHARES_GROUP = 'CLLA-All Mac Shares'

# Log level
LOG = Logger.new(STDOUT)
LOG.level = Logger::DEBUG


# Define which directory adapter to use to communicate with the directory service
## pbis uses beyondtrust's pbis tools (in /opt/pbis)
## ds uses the built-in directoryservice/opendirectoryd tools (dscl, dsmemberutil, etc.)

## NOTE: only pbis is implemented at the moment

ADAPTER = :pbis  # Can be :pbis or :ds

#####################

def main
  AD.adapter = ADAPTER
  
  shares = get_shares
  
  shares.each do |share|
    share.mount if share.is_a? Share
  end
  
  # If multiple shares were mounted, their desktop icons sometimes will overlap each other. Tell Finder to cleanup to arrange these.
  `osascript -e 'tell application "Finder" to clean up window of desktop by name'`
end


def get_shares
  shares = []
  
  groups = AD.enum_groups
  
  if groups.empty?
    LOG.warn "Warning: no group members found in #{ALL_SHARES_GROUP}"
  else
    groups.each do |group|
      data = AD.get_json(group)
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
                  if AD.check_membership(group, member_type)
                  result = AD.check_membership(group, member_type)
                  LOG.debug "Result from membership check: #{result}"
                  
                  if result
                    shares << Share.new(share)
                  else
                    LOG.debug "#{member_type} was not found to be a member of #{group}. Skipping share."
                  end
                end
              else # Hash or String
                unless obj["shares"].empty?
                  LOG.debug "Creating new share object with arg: #{obj["shares"].inspect}"
                  member_type = (obj["shares"].has_key? "member_type") ? obj["shares"]['member_type'] : 'user'
                  result = AD.check_membership(group, member_type)
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

module AD
  extend self
  
  def adapter  
    return @adapter if @adapter  
    self.adapter = :pbis  
    @adapter  
  end  
     
  def adapter=(adapter_name)  
    case adapter_name  
    when Symbol, String 
      @adapter = eval("Adapters::#{adapter_name.to_s.upcase}")
      include @adapter
    else  
      raise "Missing adapter #{adapter_name}"  
    end  
  end  
  
  def get_json(group)
    adapter.get_json(group)
  end
  
  def enum_groups
    adapter.enum_groups
  end
  
  def check_membership(group, member_type)
    adapter.check_membership(group, member_type)
  end
  
  def check_computer_membership(computername, groupname)
    adapter.check_computer_membership(computername, groupname)
  end
  
  def is_group?(group)
    adapter.is_group?(group)
  end
end

module AD  
  module Adapters  
    module PBIS  
      extend self  
      def get_json(group) 
        LOG.debug "PBIS::get_json: Getting JSON data for group #{group}"
        str = `/opt/pbis/bin/adtool -a lookup-object --dn="#{group}" --attr=info`.strip
        LOG.debug "PBIS::get_json: JSON returned for group #{group}: #{str}"
        str
      end
      
      def enum_groups
        LOG.debug "PBIS::enum_groups: Enumerating groups that are a member of #{ALL_SHARES_GROUP}"
        groups = `/opt/pbis/bin/adtool -l 2 -a search-group --name "#{ALL_SHARES_GROUP}" -t | /opt/pbis/bin/adtool -a lookup-object --dn=- --attr=member`.split
        LOG.debug "PBIS::enum_groups: #{groups.count} group members found in #{ALL_SHARES_GROUP}"
        groups
      end
      
      def check_membership(group, member_type='user')
        LOG.debug "PBIS::check_membership: Checking membership of #{member_type} in #{group}"
        case member_type
        when 'computer'
          # Since /opt/pbis/domainjoin-cli only lets us query as root, get the computer name instead and hope that it's what we joined as
          member = `scutil --get ComputerName`.strip
        else
          # Always default to current user
          member = `id -un`.strip
        end
        LOG.debug "PBIS::check_membership: #{member_type} member value being used is: #{member}"
        
        case member_type
        when 'user'
          membership_output = `/opt/pbis/bin/query-member-of --user --by-name #{member}`
          membership_output.include? group
        when 'computer'
          result = check_computer_membership(member, group)
        end
      end
      
      private
      
      def check_computer_membership(computername, groupname)
        result = `/opt/pbis/bin/adtool -a lookup-object --dn="#{groupname}" --attr=member`.strip.downcase
        unless result.include? computername
          groups = result.split
          groups.each do |group|
            if is_group?(group)
              check_computer_membership(computername, group)
            end
          end
        end
        if result.include? computername.downcase
          LOG.debug "PBIS::check_computer_membership: #{computername} was found to be a member of #{groupname}"
          return true
        else
          LOG.debug "PBIS::check_computer_membership: #{computername} was NOT found to be a member of #{groupname}. Evaluating other members for nested groups"
          groups = result.split
          LOG.debug "PBIS::check_computer_membership: #{groups.count} members found."
          groups.each do |group|
            if is_group?(group)
              LOG.debug "PBIS::check_computer_membership: #{group} is a group. Evaluating it for #{computername}"
              return true if check_computer_membership(computername, group)
            end
          end
        end
        return false
      end
      
      def is_group?(group)
        result = `/opt/pbis/bin/adtool -a lookup-object --dn="#{group}" --attr=objectClass`.strip
        result.include? "group"
      end
    end  
  end  
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
        break
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
    end
    LOG.info "#{mountname} successfully mounted."
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

main