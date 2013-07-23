###
 Roulette
  - Provides the roulette game
###

utils = require '../utils'

messages =
	start: '{{name}} has placed a bullet in the chamber and spun the barrel. Type !pulltrigger to tempt fate.'
	inProgress: 'A game of roulette is already in progress. Type !pulltrigger to play.'
	noGame: 'There is currently no loaded gun lying around. Try !roulette to start a new game.'
	death: '{{name}} lifts the gun to his head and pulls the trigger splattering his brains all over the wall. {{name}} is dead.'
	life: '{{name}} lifts the gun to his head and pulls the trigger. Nothing happens.'

games = {}

exports.init = (client) ->
	client.addListener 'message#', (nick, to, text, message) ->

		command = client.parseCmd text
		return if not command

		game = games[to]

		if command.command is 'roulette'
			if not game
				games[to] = { pullsToDeath: Math.floor(Math.random() * 6) }
				utils.log "Bullet is in chamber #{games[to].pullsToDeath + 1} (channel: #{to})"
				client.say to, utils.replace(messages.start, {name: nick})
			else
				client.say to, messages.inProgress

		else if command.command is 'pulltrigger'
			if not game
				client.say to, messages.noGame
			else
				if game.pullsToDeath is 0
					games[to] = null
					client.say to, utils.replace(messages.death, {name: nick})
				else
					game.pullsToDeath--
					client.say to, utils.replace(messages.life, {name: nick})
