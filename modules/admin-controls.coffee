###
 Admin Controls
  - Provides various admin controlling commands
###

utils = require '../utils'

exports.init = (client) ->
	client.addListener 'message', (nick, to, text, message) ->

		# Ignore commands not from out master
		return if not client.isAdmin nick

		command = client.parseCmd text
		return if not command

		if command.command is 'join'
			channel = command.input
			channel = '#' + channel if channel.substr(0, 1) isnt '#'
			client.join channel

		else if command.command is 'leave'
			if not command.input
				client.part to
			else
				channel = command.input
				channel = '#' + channel if channel.substr(0, 1) isnt '#'
				client.part channel
		
		else if command.command is 'quit' or command.command is 'exit'
			utils.log 'Quit command issued by admin'
			client.disconnect()
