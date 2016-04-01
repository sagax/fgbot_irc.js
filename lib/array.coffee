if typeof Array::last is 'undefined'
  Object.defineProperty Array.prototype, 'last',
    enumerable: false
    value: (filter) ->
      if @length is 0
        return undefined
      if typeof filter is 'function'
        i = @length - 1
        while i >= 0
          val = @[i]
          if filter(val)
            return val
          --i
        return undefined
      @[@length - 1]

  Object.defineProperty Array.prototype, 'has',
    enumerable: false
    value: (value) ->
      i = 0
      while i < @length
        if @[i] == value
          return true
        ++i
      false
