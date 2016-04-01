IRC = (server, port, password) ->
  events.EventEmitter.call this
  if typeof server is 'object'
    private_msg this, { _socket: server }, true
  else
    private_msg this, { _socket: new (net.Socket) }, true
  private_msg this, {
    _server: server
    _port: port
    _username: ''
    _cache: {}
    _callQueue: {}
    _eventPreInterceptorMap: {}
    _debugLevel: 2
    _connected: false
    _keepAliveTimer: -1
  }, true
  realEmit = @emit

  @emit = (event) ->
    if event != 'newListener'
      interceptorQueue = @_eventPreInterceptorMap[event]
      if interceptorQueue and interceptorQueue.length > 0
        i = 0
        while i < interceptorQueue.length
          if interceptorQueue[i][event].apply(this, Array::slice.call(arguments, 1)) is true
            interceptorQueue[i].__remove()
            break
          ++i
    retVal = realEmit.apply(this, arguments)
    retVal

  @_socket.setTimeout false
  @_socket.setEncoding 'ascii'
  @_socket.on 'connect', (->
    if typeof password != 'undefined'
      @_socket.write 'PASS ' + password + '\\ud\\n'
    @_socket.write 'NICK ' + @_username + '\\ud\\n'
    @_socket.write 'USER ' + @_ident + ' host server :' + @_realname + '\\ud\\n'
    return
  ).bind(this)
  @_socket.on 'close', ((had_error) ->
    @_debug 3, 'Server socket closed'
    @_stopKeepAlive()
    @_eventPreInterceptorMap = {}
    @_connected = false
    @emit 'disconnected'
    return
  ).bind(this)
  @_socket.on 'end', (->
    @_debug 3, 'Server socket end'
    @_socket.end()
    return
  ).bind(this)
  @_socket.on 'error', ((exception) ->
    @_debug 1, 'Server socket error', exception
    return
  ).bind(this)
  @_socket.on 'timeout', ((exception) ->
    @_debug 1, 'Server socket timeout', exception
    @_socket.end()
    return
  ).bind(this)
  overflow = ''
  @_socket.on 'data', ((data) ->
    data = overflow + data
    lastCrlf = data.lastIndexOf('\\ud\\n')
    if lastCrlf is -1
      overflow = data
      return
    overflow = data.substr(lastCrlf + 2)
    data = data.substr(0, lastCrlf)
    lines = data.split('\\ud\\n')
    i = 0
    while i < lines.length
      line = lines[i].trim()
      if line.length > 0
        @_processServerMessage.call this, lines[i]
      ++i
    return
  ).bind(this)
  return

parseIdentity = (identity) ->
  parsed = identity.match(/:?(.*?)(?:$|!)(?:(.*)@(.*))?/)
  {
    nick: parsed[1]
    ident: parsed[2]
    host: parsed[3]
  }

require './lib/array'
net = require('net')
util = require('util')
events = require('events')
private_msg = require('./lib/proto').private
public_msg = require('./lib/proto').public
util.inherits IRC, events.EventEmitter
public_msg IRC.prototype,
  whoami: ->
    @_username
  connect: (username, realname, ident) ->
    @_username = username
    @_realname = realname or 'user'
    @_ident = ident or 'user'
    @_socket.connect @_port, @_server
    return
  join: (channel, callback) ->
    @_socket.write 'JOIN ' + channel + '\\ud\\n'
    @_queueEventPreInterceptor
      'join': ((who, where) ->
        if who is @_username and where is channel
          if typeof callback is 'function'
            callback()
          return true
        return
      ).bind(this)
      'redirected': ((who, where, redirect) ->
        if who is @_username and where is channel
          if typeof callback is 'function'
            callback null, redirect
          return true
        return
      ).bind(this)
      'errorcode': (code, to, reason) ->
        if [
            'ERR_BANNEDFROMCHAN'
            'ERR_INVITEONLYCHAN'
            'ERR_BADCHANNELKEY'
            'ERR_CHANNELISFULL'
            'ERR_BADCHANMASK'
            'ERR_NOSUCHCHANNEL'
            'ERR_TOOMANYCHANNELS'
          ].has(code)
          if typeof callback is 'function'
            callback reason
          return true
        else if code is 'ERR_NEEDMOREPARAMS' and regarding is 'JOIN'
          if typeof callback is 'function'
            callback reason
          return true
        return
    return

  kick: (where, target, why, callback) ->
    @_socket.write 'KICK ' + where + ' ' + target + ' :' + why + '\\ud\\n'
    @_queueEventPreInterceptor
      'kick': ((who_, where_, target_, why_) ->
        if who_ is @_username and where_ is where and target_ is target
          if typeof callback is 'function'
            callback()
          return true
        return
      ).bind(this)
      'errorcode': ((code, who_, where_, reason) ->
        if [
            'ERR_NOSUCHCHANNEL'
            'ERR_BADCHANMASK'
            'ERR_CHANOPRIVSNEEDED'
            'ERR_NOTONCHANNEL'
          ].has(code) and where_ is where and who_ is @_username
          if typeof callback is 'function'
            callback reason
          return true
        else if code is 'ERR_NEEDMOREPARAMS' and where_ is 'KICK'
          if typeof callback is 'function'
            callback reason
          return true
        return
      ).bind(this)
    return

  mode: (target, modes, mask, callback) ->
    maskString = if typeof mask is 'string' then mask else undefined
    cb = if typeof mask is 'function' then mask else callback
    @_socket.write 'MODE ' + target + ' ' + modes + (if maskString then ' ' + maskString else '') + '\\ud\\n'
    @_queueEventPreInterceptor
      'mode': ((who_, target_, modes_, mask_) ->
        if who_ is @_username and target_ is target and modes_ is modes and mask_ is maskString
          if typeof cb is 'function'
            cb undefined
          return true
        return
      ).bind(this)
      'errorcode': (code, to, regarding, reason) ->
        if [
            'ERR_CHANOPRIVSNEEDED'
            'ERR_NOSUCHNICK'
            'ERR_NOTONCHANNEL'
            'ERR_KEYSET'
            'ERR_UNKNOWNMODE'
            'ERR_NOSUCHCHANNEL'
            'ERR_USERSDONTMATCH'
            'ERR_UMODEUNKNOWNFLAG'
          ].has(code)
          if typeof cb is 'function'
            cb reason
          return true
        else if code is 'ERR_NEEDMOREPARAMS' and regarding is 'JOIN'
          if typeof cb is 'function'
            cb reason
          return true
        return
    return
  names: (channel, callback) ->
    handler = (->
      @_socket.write 'NAMES ' + channel + '\\ud\\n'
      @_queueEventPreInterceptor 'names': ((where, names) ->
        @_callQueue.names.inProgress -= 1
        handled = false
        if where is channel
          if typeof callback is 'function'
            callback undefined, names
          handled = true
        if @_callQueue.names.pending.length > 0
          @_callQueue.names.pending.shift()()
        handled
      ).bind(this)
      return
    ).bind(this)
    queue = @_callQueue.names = @_callQueue.names or
      inProgress: 0
      pending: []
    queue.inProgress += 1
    if queue.inProgress > 1
      queue.pending.push handler
    else
      handler()
    return
  whois: (nick, callback) ->
    handler = (->
      @_socket.write 'WHOIS ' + nick + '\\ud\\n'
      @_queueEventPreInterceptor
        'whois': ((who, whois) ->
          @_callQueue.whois.inProgress -= 1
          handled = false
          if nick is who
            if typeof callback is 'function'
              callback undefined, whois
            handled = true
          if @_callQueue.whois.pending.length > 0
            @_callQueue.whois.pending.shift()()
          handled
        ).bind(this)
        'errorcode': (code, to, regarding, reason) ->
          if [
              'ERR_NOSUCHSERVER'
              'ERR_NONICKNAMEGIVEN'
              'RPL_WHOISUSER'
              'RPL_WHOISCHANNELS'
              'RPL_WHOISCHANNELS'
              'RPL_WHOISSERVER'
              'RPL_AWAY'
              'RPL_WHOISOPERATOR'
              'RPL_WHOISIDLE'
              'ERR_NOSUCHNICK'
              'RPL_ENDOFWHOIS'
            ].has(code)
            if typeof cb is 'function'
              cb reason
            return true
          else if code is 'ERR_NEEDMOREPARAMS' and regarding is 'JOIN'
            if typeof cb is 'function'
              cb reason
            return true
          return
      return
    ).bind(this)
    queue = @_callQueue.whois = @_callQueue.whois or
      inProgress: 0
      pending: []
    queue.inProgress += 1
    if queue.inProgress > 1
      queue.pending.push handler
    else
      handler()
    return
  nick: (newnick, callback) ->
    @_socket.write 'NICK ' + newnick + '\\ud\\n'
    @_queueEventPreInterceptor
      'connected': ->
        true
      'nick': ((oldn, newn) ->
        if oldn is @_username
          @_username = newnick
          if typeof callback is 'function'
            callback undefined, oldn, newn
          return true
        return
      ).bind(this)
      'errorcode': ((code, who, regarding, reason) ->
        if [ 'ERR_NONICKNAMEGIVEN' ].has(code)
          if typeof callback is 'function'
            callback regarding
          return true
        else if [
            'ERR_NICKNAMEINUSE'
            'ERR_NICKCOLLISION'
            'ERR_ERRONEUSNICKNAME'
          ].has(code)
          if typeof callback is 'function'
            callback reason
          return true
        return
      ).bind(this)
    return
  part: (channel, callback) ->
    @_socket.write 'PART ' + channel + '\\ud\\n'
    @_queueEventPreInterceptor
      'part': ((who_, where_) ->
        if who_ is @_username and where_ is channel
          if typeof callback is 'function'
            callback undefined
          return true
        return
      ).bind(this)
      'errorcode': ((code, who, regarding, reason) ->
        if [
            'ERR_NOSUCHCHANNEL'
            'ERR_NOTONCHANNEL'
          ].has(code)
          if typeof cb is 'function'
            cb reason
          return true
        else if code is 'ERR_NEEDMOREPARAMS' and regarding is 'JOIN'
          if typeof cb is 'function'
            cb reason
          return true
        return
      ).bind(this)
    return
  ping: (to) ->
    @_socket.write 'PRIVMSG ' + to + ' :\\u1PING ' + Date.now() + '\\u1\\ud\\n'
    return
  privmsg: (to, message) ->
    @_socket.write 'PRIVMSG ' + to + ' :' + message + '\\ud\\n'
    return
  notice: (to, message) ->
    @_socket.write 'NOTICE ' + to + ' :' + message + '\\ud\\n'
    return
  raw: (message) ->
    @_socket.write message + '\\ud\\n'
    return
  quit: (message) ->
    @_socket.write 'QUIT :' + message + '\\ud\\n'
    @_socket.end()
    return
  setDebugLevel: (level) ->
    @_debugLevel = level
    return

private_msg IRC.prototype,
  _startKeepAlive: (server) ->
    if @_keepAliveTimer != -1
      @_stopKeepAlive()
    self = this
    @_keepAliveTimer = setInterval((->
      self._socket.write 'PING ' + server + '\\ud\\n'
      return
    ), 60000)
    return
  _stopKeepAlive: ->
    if @_keepAliveTimer is -1
      return
    clearInterval @_keepAliveTimer
    @_keepAliveTimer = -1
    return
  _debug: (level, text, data) ->
    if level <= @_debugLevel
      console.log text
    return
  _queueEventPreInterceptor: (interceptor) ->
    interceptorQueues = []
    private_msg interceptor, __remove: ->
      i = 0
      while i < interceptorQueues.length
        interceptorQueue = interceptorQueues[i]
        index = interceptorQueue.indexOf(interceptor)
        if index != -1
          interceptorQueue.splice index, 1
        ++i
      return
    for event of interceptor
      interceptorQueue = @_eventPreInterceptorMap[event]
      if typeof interceptorQueue is 'undefined'
        interceptorQueue = @_eventPreInterceptorMap[event] = []
      interceptorQueue.push interceptor
      interceptorQueues.push interceptorQueue
    return
  _errorHandler: (code, raw, server, to, regarding, reason) ->
    @emit 'errorcode', code, to, regarding, reason
    return
  _messageHandlers:
    '401': 'ERR_NOSUCHNICK'
    '402': 'ERR_NOSUCHSERVER'
    '403': 'ERR_NOSUCHCHANNEL'
    '404': 'ERR_CANNOTSENDTOCHAN'
    '405': 'ERR_TOOMANYCHANNELS'
    '406': 'ERR_WASNOSUCHNICK'
    '407': 'ERR_TOOMANYTARGETS'
    '409': 'ERR_NOORIGIN'
    '411': 'ERR_NORECIPIENT'
    '412': 'ERR_NOTEXTTOSEND'
    '413': 'ERR_NOTOPLEVEL'
    '414': 'ERR_WILDTOPLEVEL'
    '421': 'ERR_UNKNOWNCOMMAND'
    '422': 'ERR_NOMOTD'
    '423': 'ERR_NOADMININFO'
    '424': 'ERR_FILEERROR'
    '431': 'ERR_NONICKNAMEGIVEN'
    '432': 'ERR_ERRONEUSNICKNAME'
    '433': 'ERR_NICKNAMEINUSE'
    '436': 'ERR_NICKCOLLISION'
    '441': 'ERR_USERNOTINCHANNEL'
    '442': 'ERR_NOTONCHANNEL'
    '443': 'ERR_USERONCHANNEL'
    '444': 'ERR_NOLOGIN'
    '445': 'ERR_SUMMONDISABLED'
    '446': 'ERR_USERSDISABLED'
    '451': 'ERR_NOTREGISTERED'
    '461': 'ERR_NEEDMOREPARAMS'
    '462': 'ERR_ALREADYREGISTRED'
    '463': 'ERR_NOPERMFORHOST'
    '464': 'ERR_PASSWDMISMATCH'
    '465': 'ERR_YOUREBANNEDCREEP'
    '467': 'ERR_KEYSET'
    '471': 'ERR_CHANNELISFULL'
    '472': 'ERR_UNKNOWNMODE'
    '473': 'ERR_INVITEONLYCHAN'
    '474': 'ERR_BANNEDFROMCHAN'
    '475': 'ERR_BADCHANNELKEY'
    '481': 'ERR_NOPRIVILEGES'
    '482': 'ERR_CHANOPRIVSNEEDED'
    '483': 'ERR_CANTKILLSERVER'
    '491': 'ERR_NOOPERHOST'
    '501': 'ERR_UMODEUNKNOWNFLAG'
    '502': 'ERR_USERSDONTMATCH'
    '001': (raw, from, to, text) ->
      @_username = to
      if @_connected
        return
      @_connected = true
      @emit 'connected', text
      @_startKeepAlive from
      return
    '375': (raw) ->
      @_messageHandlers['372'].apply this, arguments
    '372': (raw, from, to, text) ->
      @emit 'servertext', from, to, text, raw
      return
    '376': (raw, from, text) ->
      @_messageHandlers['372'].apply this, arguments
    '353': (raw, from, to, type, where, names) ->
      @_cache['names'] = @_cache['names'] or {}
      @_cache['names'][where] = (@_cache['names'][where] or []).concat(names.split(' '))
      return
    '366': (raw, from, to, where) ->
      namesCache = @_cache['names'] or []
      names = namesCache[where] or []
      @emit 'names', where, names
      if @_cache['names'] and @_cache['names'][where]
        delete @_cache['names'][where]
      return
    '311': (raw, from, to, nick, ident, host, noop, realname) ->
      @_cache['whois'] = @_cache['whois'] or {}
      whois = @_cache['whois'][nick] = @_cache['whois'][nick] or {}
      whois.nick = nick
      whois.ident = ident
      whois.host = host
      whois.realname = realname
      return
    '319': (raw, from, to, nick, channels) ->
      @_cache['whois'] = @_cache['whois'] or {}
      whois = @_cache['whois'][nick] = @_cache['whois'][nick] or {}
      whois.channels = (whois.channels or []).concat(channels.replace(/[\+@]([#&])/g, '$1').split(' '))
      return
    '318': (raw, from, to, nick) ->
      @_cache['whois'] = @_cache['whois'] or {}
      whois = @_cache['whois'][nick] = @_cache['whois'][nick] or {}
      @emit 'whois', nick, whois
      if @_cache['whois'] and @_cache['whois'][nick]
        delete @_cache['whois'][nick]
      return
    '331': (raw, from, to, where, topic) ->
      @emit 'topic', where, null, null, raw
      return
    '332': (raw, from, to, where, topic) ->
      @emit 'topic', where, topic, null, raw
      return
    '470': (raw, from, to, original, redirect) ->
      @emit 'redirected', to, original, redirect
      return
    '333': (raw, from, to, where, who, timestamp) ->
      identity = parseIdentity(who)
      @emit 'topicinfo', where, identity.nick, timestamp
      return
    'PING': (raw, from) ->
      @_socket.write 'PONG :' + from + '\\ud\\n'
      return
    'PONG': (raw, from) ->
    'MODE': (raw, who, target, modes, mask) ->
      identity = parseIdentity(who)
      @emit 'mode', identity.nick, target, modes, mask, raw
      return
    'TOPIC': (raw, who, channel, topic) ->
      identity = parseIdentity(who)
      @emit 'topic', channel, topic, identity.nick, raw
      return
    'PRIVMSG': (raw, from, to, message) ->
      identity = parseIdentity(from)
      @emit 'privmsg', identity.nick, to, message, raw
      return
    'NOTICE': (raw, from, to, message) ->
      identity = parseIdentity(from)
      @emit 'notice', identity.nick, to, message, raw
      return
    'JOIN': (raw, who, channel) ->
      identity = parseIdentity(who)
      @emit 'join', identity.nick, channel, raw
      return
    'KICK': (raw, who, where, target, why) ->
      identity = parseIdentity(who)
      @emit 'kick', identity.nick, where, target, why, raw
      return
    'NICK': (raw, from, data) ->
      `var data`
      # :Angel!foo@bar NICK newnick
      identity = parseIdentity(from)
      data = data.match(/:?(.*)/)
      if !data
        throw 'invalid NICK structure'
      if from is @_username
        @_username = newnick
      @emit 'nick', identity.nick, data[1], raw
      return
    'PART': (raw, who, where) ->
      identity = parseIdentity(who)
      @emit 'part', identity.nick, where, raw
      return
    'QUIT': (raw, who, message) ->
      identity = parseIdentity(who)
      @emit 'quit', identity.nick, message, raw
      return
    'CTCP_PRIVMSG_PING': (raw, from, to, data) ->
      identity = parseIdentity(from)
      @emit 'ping', identity.nick
      @_socket.write 'NOTICE ' + identity.nick + ' :\\u1PING ' + data + '\\u1\\ud\\n'
      return
    'CTCP_NOTICE_PING': (raw, from, to, data) ->
      identity = parseIdentity(from)
      @emit 'ping-reply', identity.nick, Date.now() - Number(data)
      return
    'CTCP_PRIVMSG_ACTION': (raw, from, to, data) ->
      identity = parseIdentity(from)
      @emit 'action', identity.nick, to, data, raw
      return
  _processServerMessage: (line) ->
    `var handler`
    @_debug 4, 'Incoming: ' + line
    @emit 'raw', line
    # ctcp handling should be rewritten
    matches = line.match(/^:([^\s]*)\s([^\s]*)\s([^\s]*)\s:\u0001([^\s]*)\s(.*)\u0001/)
    if matches
      handler = @_messageHandlers['CTCP_' + matches[2] + '_' + matches[4]]
      if typeof handler != 'undefined'
        handler.call this, line, matches[1], matches[3], matches[5]
      else
        @_debug 2, 'Unhandled ctcp: ' + line
      return
    # anything other than ctcp
    parts = line.trim().split(RegExp(' :'))
    args = parts[0].split(' ')
    if parts.length > 1
      args.push parts.slice(1).join(' :')
    if line.match(/^:/)
      args[1] = args.splice(0, 1, args[1])
      args[1] = (args[1] + '').replace(/^:/, '')
    command = args[0].toUpperCase()
    args = args.slice(1)
    args.unshift line
    handler = @_messageHandlers[command]
    if typeof handler is 'function'
      handler.apply this, args
    else if typeof handler is 'string'
      args.unshift handler
      @_errorHandler.apply this, args
    else
      @_debug 2, 'Unhandled msg: ' + line
    return
exports.IRC = IRC
