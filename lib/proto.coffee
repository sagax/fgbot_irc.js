exports.private = (target, source, writable) ->
  Object.keys(source).forEach (name) ->
    Object.defineProperty target, name,
      enumerable: false
      value: source[name]
      writable: writable == true
    return
  return

exports.public = (target, source, writable) ->
  Object.keys(source).forEach (name) ->
    Object.defineProperty target, name,
      enumerable: true
      value: source[name]
      writable: writable == true
    return
  return
