# Datetime Helper module
module DatetimeHelper
  def self.pretty_datetime(datetime)
    return datetime.localtime.strftime('%b %d, %Y %I:%M %p')
  end
  
  def self.pretty_date(date)
    return date.localtime.strftime('%b %d, %Y')
  end
  
  def self.pretty_time(time)
    return time.localtime.strftime('%I:%M %p')
  end
end