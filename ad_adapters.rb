module ADAdapters
  extend self
  
  def adapter  
    return @adapter if @adapter  
    self.adapter = :pbis  
    @adapter  
  end  
     
  def adapter=(adapter_name)  
    case adapter_name  
    when Symbol, String 
      @adapter = eval("#{adapter_name.to_s.upcase}")
      include @adapter
    else  
      raise "Missing adapter #{adapter_name}"  
    end  
  end  
  
  def get_info(group)
    adapter.get_info(group)
  end
  
  def get_groups(objectName, objectType)
    adapter.get_groups(objectName, objectType)
  end
  
  def extract_cns(arr)
    # use a substitution to remove CN=, system ruby 1.8.7 regex doesn't support lookbehinds
    arr.collect{ |g| "#{g[/([^,])*/].gsub("CN=", "").downcase.strip}" } 
  end
end

require File.expand_path(File.dirname(__FILE__) + '/ad_adapters/ds')
require File.expand_path(File.dirname(__FILE__) + '/ad_adapters/pbis')