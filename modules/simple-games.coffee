###
 Simple Games
  - Provides some simple games
###

utils = require '../utils'

roulette = 
	pullsToDeath: false
	messages:
		start: '{{name}} has placed a bullet in the chamber and spun the barrel. Type !pulltrigger to tempt fate.'
		inProgress: 'A game of roulette is already in progress. Type !pulltrigger to play.'
		noGame: 'There is currently no loaded gun lying around. Try !roulette to start a new game.'
		death: '{{name}} lifts the gun to his head and pulls the trigger splattering his brains all over the wall. {{name}} is dead.'
		life: '{{name}} lifts the gun to his head and pulls the trigger. Nothing happens.'

exports.init = (client) ->
	client.addListener 'message#', (nick, to, text, message) ->

		command = client.parseCmd text
		return if not command

		if command.command is 'roulette'
			if roulette.pullsToDeath is false
				roulette.pullsToDeath = Math.floor(Math.random() * 6)
				utils.log roulette.pullsToDeath
				client.say to, utils.replace(roulette.messages.start, {name: nick})
			else
				client.say to, roulette.messages.inProgress

		else if command.command is 'pulltrigger'
			if roulette.pullsToDeath is false
				client.say to, roulette.messages.noGame
			else
				if roulette.pullsToDeath is 0
					roulette.pullsToDeath = false
					client.say to, utils.replace(roulette.messages.death, {name: nick})
				else
					roulette.pullsToDeath--
					client.say to, utils.replace(roulette.messages.life, {name: nick})
