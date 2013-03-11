require 'open3'

module ADAdapters
  module PBIS  
    extend self  

    def get_info(group) 
      LOG.debug "PBIS::get_info: Getting JSON data for group #{group}"
      str = `/opt/pbis/bin/adtool -a lookup-object --dn="#{group}" --attr=info`.strip
      LOG.debug "PBIS::get_info: Info attr data returned for group #{group}: #{str}"
      str
    end
    
    def get_groups(objectName, objectType)
      LOG.debug "gettings subgroups of #{objectName}, which is of type #{objectType}"
      
      computerName = `scutil --get ComputerName`.strip
      currentUser = `id -un`.strip
      
      if objectType == "user"
        raw_groups = `/opt/pbis/bin/list-groups-for-user #{currentUser}`.strip
        raw_groups = raw_groups.split("\n")
        raw_groups.shift # Remove first line: summary output
        group_names = []
        groups = []
        raw_groups.each do |group|
          group_names << /name = ([^\s]*)/.match(group)[1]
        end
        group_names.compact!
        
        group_names.each do |group|
          cmd = "/opt/pbis/bin/adtool -a search-group --name '#{group}'"
          Open3.popen3(cmd) do |stdin, stdout, stderr|
            err = stderr.read
            out = stdout.read
              
            dn = out.split("\n").first
            groups << dn.strip unless dn.nil? || dn.empty?
          end
        end
        
        puts groups.inspect
          
      else
        case objectType
        when "computer"
          action = "search-computer"
        when "group"
          action = "search-group"
        else
          LOG.error "Unknown object type: #{objectName}"
          exit
        end
      
        groups = nil
        dn = nil
        # Why not pipe these two commands together? Great question.
        # I can't reproduce it in any other environment, but when I pipe these together the second cmd
        #  can't read the keytab, as if it were not being run as root.
      
        if currentUser == "root"
          cmd = "/opt/pbis/bin/adtool -k /etc/krb5.keytab -n '#{computerName.upcase}$' -a #{action} --name '#{objectName}'"
        else
          cmd = "/opt/pbis/bin/adtool -a #{action} --name '#{objectName}'"
        end
      
        Open3.popen3(cmd) do |stdin, stdout, stderr|
          err = stderr.read
          out = stdout.read
              
          dn = out.split("\n").first
          dn.strip! if dn
        end
      
        unless dn.nil? || dn.empty?
          if currentUser == "root"
            cmd = "/opt/pbis/bin/adtool -k /etc/krb5.keytab -n '#{computerName.upcase}$' -a lookup-object --dn='#{dn}' --attr=memberOf'"
          else
            cmd = "/opt/pbis/bin/adtool -a lookup-object --dn='#{dn}' --attr=memberOf"
          end
        
          Open3.popen3(cmd) do |stdin, stdout, stderr|
            err = stderr.read
            out = stdout.read
            groups = out
          end
        else
          LOG.warn "Unable to determine DN for object: #{objectName}"
          return nil
        end
      end
      
      
      if groups.nil? || groups.empty?
        LOG.debug "No more groups for #{objectName}\n\n"
        return
      else
        groups = groups.split("\n") unless groups.is_a? Array # split into an array by line
        # groups = ADAdapters.extract_cns(groups)
    
        LOG.debug "Found #{groups.count} groups: #{groups.inspect}"
        immu_groups = Array.new groups
        immu_groups.each do |group|
          LOG.debug "\nContinuing recursion from #{objectName} with group: #{group}"
          new_groups = get_groups(group, "group")
          new_groups.compact.map {|g| groups << g unless groups.include? g } unless new_groups.nil?
        end
        LOG.debug "End of recursion for #{objectName}\n\n"
      end
      groups
    end
  end
end