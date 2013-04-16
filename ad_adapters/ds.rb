module ADAdapters
  module DS
    ADGroupAttribute = 'dsAttrTypeNative:memberOf'
      
    extend self  
    def get_info(group)
      LOG.debug "DS::get_info: Getting JSON data for group #{group}"
      # Get info attribute. dscl prepends the attribute name and a newline - remove those
      str = `dscl /Search read "/Groups/#{group}" dsAttrTypeNative:info`.split("\n").map { |i| i.strip }
      str.shift
      LOG.debug "DS::get_info: Info attr data returned for group #{group}: #{str}"
      str[0]
    end
    
    def get_groups(objectName, objectType="computer")
      LOG.debug "-- Gettings subgroups of #{objectName}, which is of type #{objectType}."
      case objectType
      when "user"
        groups = `dscl /Search read "/Users/#{objectName}" #{ADGroupAttribute} 2>&1`
        exit_code = $?
      when "computer"
        groups = `dscl /Search read "/Computers/#{objectName}$" #{ADGroupAttribute} 2>&1`
        exit_code = $?
      when "group"
        groups = `dscl /Search read "/Groups/#{objectName}" #{ADGroupAttribute} 2>&1`
        exit_code = $?
      end
  
      if groups.empty? || groups.strip == "No such key: #{ADGroupAttribute}" || exit_code != 0
        LOG.debug "-- No more groups for #{objectName}."
        return
      else
        LOG.debug("-- Raw group output: #{groups.inspect}")
        
        groups = clean_group_output(groups)

        LOG.debug("-- Cleaned group output: #{groups.inspect}")
        LOG.debug("-- Extracting CNs from DNs")
        groups = ADAdapters.extract_cns(groups) unless groups.nil?
    
        LOG.debug "-- Found #{groups.count} groups: #{groups.inspect}."
        immu_groups = Array.new groups
        immu_groups.each do |group|
          LOG.debug "Continuing recursion from #{objectName} with group: #{group}"
          new_groups = get_groups(group, "group")
          new_groups.compact.map {|g| groups << g unless groups.include? g } unless new_groups.nil?
        end
        LOG.debug "End of recursion for #{objectName}"
      end
      groups
    end
    
    private 
    
    def clean_group_output(groups)
      groups = groups.split("\n") # split into an array by line
      groups.map! {|m| m unless m.include? "No such key" }.compact! # remove potential no-match output from other directories in the search path
      # Assume what we have left is an output of DNs (prefixed by the key name) potentially on multiple lines
      groups.map! do |line|
        line = line.split(" ")
        line.map {|m| m unless m.include? ADGroupAttribute }.compact! # remove key prefix in the output
      end
      
      groups.compact.flatten
    end
  end
end