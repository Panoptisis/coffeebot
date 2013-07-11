###
 Test Module
  - Responds to !test
###

exports.init = (client) ->
	client.addListener 'message', (nick, to, text, message) ->
		
		command = client.parseCmd text

		if command and command.command is 'test'
			client.sayBack nick, to, 'I heard you'