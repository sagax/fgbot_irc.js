exports.fake = (source) ->
  object = {}
  methods = []

  if Object::toString.call(source) is '[object Object]'
    names = Object.getOwnPropertyNames(source)
    for i of names
      member = source[names[i]]
      if typeof member == 'function'
        methods.push names[i]
  else if Object::toString.call(source) is '[object Array]'
    methods = source

  methods.forEach (name, i) ->
    Object.defineProperty object, name,
      enumerable: false
      value: ->
        object[name].history.push arguments
        if object[name].nextHandler.length > 0
          handler = object[name].nextHandler.pop()
          return handler.apply(this, arguments)
        object[name].defaultReturnValue

    Object.defineProperties object[name],
      history:
        enumerable: false
        value: []
      nextHandler:
        enumerable: false
        value: []
      next:
        enumerable: false
        value: (handler) ->
          object[name].nextHandler.push handler
          return
      returns:
        enumerable: false
        value: (value) ->
          object[name].defaultReturnValue = value
          return

    return
  object
