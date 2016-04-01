IRC = require('./IRC').IRC
irc = new IRC('irc.freenode.net', 6667)
irc.on 'raw', (data) ->
  console.log data
  return
# irc.setDebugLevel(1);
irc.on 'connected', (server) ->
  console.log 'connected to ' + server
  irc.join '#foobartest', (error) ->
    irc.privmsg '#foobartest', 'well hello yall'
    irc.nick 'muppetty2', (old, newn) ->
      irc.privmsg '#foobartest', 'I\'m new!'
      return
    return
  return
irc.on 'topic', (where, topic) ->
  console.log 'topic of ' + where + ': ' + topic
  return
irc.on 'quit', (who, message) ->
  console.log who + ' quit: ' + message
  return
irc.on 'part', (who, channel) ->
  console.log who + ' left ' + channel
  return
irc.on 'kick', (who, channel, target, message) ->
  console.log target + ' was kicked from ' + channel + ' by ' + who + ': ' + message
  return
irc.on 'names', (channel, names) ->
  console.log channel + ' users: ' + names
  return
irc.on 'privmsg', (from, to, message) ->
  console.log '<' + from + '> to ' + to + ': ' + message
  if to[0] == '#'
    irc.privmsg to, 'hi ' + from
  else
    irc.privmsg from, 'hi!'
  return
irc.on 'mode', (who, target, modes, mask) ->
  console.log who + ' set mode ' + modes + (if mask then ' ' + mask else '') + ' on ' + target
  return
irc.on 'servertext', (from, to, text) ->
  console.log '(' + from + ') ' + text
  return
irc.on 'ping', (from) ->
  console.log 'ping from ' + from
  irc.ping from
  return
irc.on 'ping-reply', (from, ms) ->
  console.log 'ping reply from ' + from + ': ' + ms + ' ms'
  return
irc.on 'errorcode', (code) ->
  if code == 'ERR_NICKNAMEINUSE'
    irc.nick 'foomeh2'
  return
irc.connect 'foomeh', 'my name yeah', 'ident'
process.on 'exit', ->
  irc.quit 'bye'
  return
