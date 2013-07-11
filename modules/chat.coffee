###
 Chat Support
  - Provides various chat-related commands
###

exports.init = (client) ->
	client.addListener 'message', (nick, to, text, message) ->

		command = client.parseCmd text
		return if not command

		if command.command is 'say'
			client.sayBack nick, to, command.input

		else if command.command is 'sayto'
			to = command.input.split(' ').splice(0, 1)[0]
			msg = command.input.substr(to.length)
			client.say to, msg