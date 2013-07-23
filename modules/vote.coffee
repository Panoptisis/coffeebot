###
 Vote module
###

votes = {}

optionString = (options) ->
	result = []
	for option in options
		result.push "(#{option.id}) #{option.name}"
	return result.join(', ')

incrementVote = (vote, id) ->
	for option in vote.options
		if option.id is parseInt(id)
			option.votes++
			return true
	return false


exports.init = (client) ->
	client.addListener 'message#', (nick, to, text, message) ->
		
		command = client.parseCmd text
		return if not command

		# Get the vote object for this channel
		vote = votes[to]

		if command.command is 'callvote'

			# Make sure a vote isn't already in progress
			if vote
				client.sayBack nick, to, 'A vote is already in progress.'
				return

			options = []
			i = 1
			for option in command.input.split ' '
				options.push
					id: i
					name: option
					votes: 0
				i++

			# Make sure they had a sane number of options
			if options.length < 2
				client.sayBack nick, to, 'A vote needs at least two options.'
				return
			else if options.length > 10
				client.sayBack nick, to, 'A vote cannot have more than 10 options.'
				return

			vote = 
				options: options
				voters: []
				starter: nick
			votes[to] = vote

			client.sayBack nick, to, "A vote has been called with the following options: #{optionString(vote.options)}."
			client.sayBack nick, to, 'Type "!vote [option number]" to vote.'
			client.say nick, 'Type "!tally" when you want to close the vote.'

		else if command.command is 'vote'

			# Make sure a vote is in progress
			if not vote
				client.sayBack nick, to, 'There is no vote in progress.'
				return

			# Make sure this person hasn't voted
			if vote.voters.indexOf(nick) isnt -1
				client.say nick, 'You have already voted.'
				return

			if not incrementVote(vote, command.input)
				client.say nick, 'Invalid vote option.'
				return

			vote.voters.push nick

		else if command.command is 'tally'

			# Make sure a vote is in progress
			if not vote
				client.sayBack nick, to, 'There is no vote in progress.'
				return

			if nick isnt vote.starter and not client.isAdmin nick
				client.sayBack nick, to, "Only #{starter} can end the vote."
				return

			client.sayBack nick, to, 'The vote has ended. Here are the results:'
			for option in vote.options
				client.sayBack nick, to, " - #{option.name}: #{option.votes}"

			votes[to] = null
