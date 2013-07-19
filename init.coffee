###
 IRC Bot
  - Sets up our little bot fellow.
###

# Includes
irc    = require('irc')
utils  = require('./utils')
config = require('./config').config

utils.log 'Starting bot...'
# Set up our bot
client = new irc.Client config.server, config.nick, {
		userName: config.nick
		realName: config.nick
	}


# Set up some necessary listeners
client.addListener 'error', (message) ->

	# If we don't log messages, node dies
	console.log "Error: #{message}"


# Do init things
client.addListener 'registered', (message) ->

	utils.log 'Connected to server'

	# Identify before we register
	client.say 'NickServ', "IDENTIFY #{config.password}"
	utils.log 'Identified with NickServ'

	# Join after we've registered and all that jaz
	for channel in config.channels
		client.join channel

	utils.log "Joined #{config.channels.length} channel(s)"


# Attach configs to the client for easy access
client.config = config


# Create a nice helper method on the bot
client.sayBack = (from, to, message) ->
	to = from if to is config.nick
	this.say to, message


# This is super useful, so attach it also
client.parseCmd = (message) ->

	message = '' + message
	if message.substr(0, 1) isnt '!' or message.length < 2
		return false
	message = message.substr(1)

	command = 
		command: ''
		input: null

	parts = message.split(' ')
	command.command = parts.splice(0, 1)[0].toLowerCase()
	if parts.length > 0
		command.input = parts.join(' ')

	return command


# Determins whether or not the given nick can control this bot
client.isAdmin = (nick) ->
	return nick is this.config.admin


# Print debug messages
if config.debug
	client.addListener 'message', (nick, to, text, message) ->
		if to is config.nick
			utils.log "Message from #{nick}: #{text}"


# Export things
exports.client = client
