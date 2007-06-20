require 'open-uri'
#require 'date'
require 'time'
#NOTE: Use time instead of date for speed reasons. See:
#http://www.recentrambles.com/pragmatic/view/33


module WikiHelper


  def review_dokuwiki(_assignment_url, _start_date = nil, _wiki_user = nil)

    response = '' #the response from the URL

    #Check to make sure we were passed a valid URL
    matches = /http:/.match( _assignment_url )
    if not matches
      return response
    end

    #Args
    #TODO: Add check to remove trailing slash if provided
    url = _assignment_url
    wiki_url = _assignment_url.scan(/(.*?)dokuwiki/)
    namespace = _assignment_url.split(/\//)
    namespace_url = namespace.last

    #Doku Wiki Specific
    index = "?idx=" + namespace_url
    review = "?do=revisions" #"?do=recent"


    #Grab all relevant urls from index page ####################
    url += index
    open(url, 
         "User-Agent" => "Ruby/#{RUBY_VERSION}",
         "From" => "email@addr.com", #Put pg admin email address here
         "Referer" => "http://") { |f| #Put pg URL here
      
      # Save the response body
      response = f.read
      
    }

    #Clean URLs
    response = response.gsub(/\/dokuwiki/,wiki_url[0].to_s + 'dokuwiki')

    #Get all URLs 
    index_urls = response.scan(/href=\"(.*?)\"/)
    
    namespace_urls = Array.new #Create array to store all URLs in this namespace
    namespace_urls << _assignment_url

    #Narrow down to all URLs in our namespace
    index_urls.each_with_index do |index_url, index| 
      
      scan_result = index_url[0].scan(_assignment_url + ":") #scan current item
      
      if _assignment_url + ":" === scan_result[0] 
        namespace_urls << index_urls[index].to_s 
      end
      
    end

    #Create a array for all of our review_items
    review_items = Array.new

    #Process Each page in our namespace
    namespace_urls.each_with_index do |cur_url, index| 
      
      #return cur_url + review
      url = namespace_urls[index].to_s 
      url += review
      #return url
      open(url, 
           "User-Agent" => "Ruby/#{RUBY_VERSION}",
           "From" => "email@addr.com", #Put pg admin email address here
           "Referer" => "http://") { |f| #Put pg URL here
        
        # Save the response body
        response = f.read
        
      }
      
      ## DOKUWIKI PARSING
      
      #Clean URLs
      response = response.gsub(/\/dokuwiki/,wiki_url[0].to_s + 'dokuwiki')
      
      # Luckily, dokuwiki uses a structure like:
      # <!-- wikipage start -->  
      # Content
      # <!-- wikipage stop -->
      # 
      #Get everything between the words "wikipage"
      changes = response.split(/wikipage/) 
      #Trim the "start -->" from "<!-- wikipage start -->"
      changes = changes[1].sub(/start -->/,"") 
      #Trim the "<!--" from "<!-- wikipage stop -->"
      response = changes.sub(/<!--/,"") 
      
      
      #Extract each line item
      line_items = response.scan(/<li>(.*?)<\/li>/)
      
      #Extract the dates only
      dates = response.scan(/\d\d\d\d\/\d\d\/\d\d \d\d\:\d\d/) 
      
      
      #if wiki username provided we only want their line items
      if _wiki_user
        
        #Remove line items that do not contain this user
        line_items.each_with_index do |item, index| 
          
          scan_result = item[0].scan(_wiki_user) #scan current item
          
          if not _wiki_user === scan_result[0] #no match for wiki user --> eliminate
            line_items[index] = nil  
            dates[index] = nil
          end
          
        end
        
        line_items.compact!
        dates.compact!
      end
      
      #if start date provided we only want date line items since start date
      if _start_date
        
        
        #NOTE: The date_lines index = dates index
        
        #Convert _start_date
        start_date = Time.parse(_start_date)
        
        #Remove dates before deadline
        dates.each_with_index do |date, index| 
          
          #The date is before start of review
          if Time.parse(date) < start_date
            line_items.delete_at(index)
          end
          
        end
        
      end
    

      review_items = review_items + line_items
      
    end

    return review_items
      

  end


end
