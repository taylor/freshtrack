module FreshBooks
  class Invoice
    TYPE_MAPPINGS['date'] = Date
    
    def open?
      !%w[draft paid].include?(status)
    end
    
    def client
      Client.get(client_id)
    end
    
    attr_accessor :number
    
    alias_method :old_brackets, :[]
    def [](m)
      if m.to_s == 'number'
        self.number
      else
        old_brackets(m)
      end
    end

    alias_method :old_brackets_equal, :[]=
    def []=(m, v)
      if m.to_s == 'number'
        self.number = v 
      else
        old_brackets_equal(m, v)
      end
    end
    
    class << self
      alias_method :old_members, :members
      def members
        old_members + ['number']
      end
    end
  end
end