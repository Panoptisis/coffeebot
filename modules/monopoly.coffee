###
 Monopoly
  - The game of Monopoly
###

utils = require '../utils'

games = {}

exports.init = (client) ->
	client.addListener 'message#', (nick, to, text, message) ->

		# For now, only respond on a few channels
		if to isnt '#test' and to isnt '#monopoly'
			return

		# Ignore noon-commands
		command = client.parseCmd text
		return if not command

		# Help command trumps all
		if command.command is 'monopoly-help'

			# TODO: Help junk here
			
			return

		# Load up the game for this channel
		game = games[to]

		if command.command is 'monopoly'
			if game
				client.say to, 'A game of monopoly is already in progress.'
				return

			game = new Game(to, client)
			client.say to, "#{nick} has started a game of monopoly. Type \"!join [game token]\" to join the game."
			client.say to, "Available tokens are: #{game.getTokenString()}"
			client.say to, 'The game will start in 5 minutes.'
			games[to] = game
			setTimeout game.triggerStart, 10000 #300000

			return
		
		# Return if we have no game, son
		return if not game

		# Get the player if there is one
		player = game.getPlayer nick

		# Do things where the player doesn't have to exist first
		if not player and game.stage is 'join' and command.command is 'join'
			player = new Player(game, nick)
			valid = game.takeToken player, command.input

			if valid
				game.addPlayer player
				client.say to, "#{nick} has joined the game using the #{player.token} token."
			else
				client.say to, "#{nick} has chosen an invalid or taken token."

		# Die if we don't meet requirements
		return if not player or game.stage is 'join'

		# Answer status calls
		if command.command is 'status'
			command.input = nick if not command.input
			game.playerStatus command.input
			return

		# Property information command
		if command.command is 'property'
			if not command.input
				game.say 'You must provide a property ID.'
			else
				game.propertyInfo command.input
			return

		# Answer roll calls (har har puns)
		if command.command is 'roll'
			if nick isnt game.getCurrentPlayer().nick
				game.say 'It is not your turn.'
				return

			# Make sure we can roll now
			return if game.stage isnt 'preroll'

			game.triggerTurnRoll()
			return

		# Buy property
		if command.command is 'buy' or command.command is 'auction'
			# Make sure the conditions are right
			return if nick isnt game.getCurrentPlayer().nick
			return if game.stage isnt 'sell property'

			game.triggerPropertyPurchase() if command.command is 'buy'
			game.triggerPropertyAuction() if command.command is 'auction'

			return

		# Bidding
		if command.command is 'bid'
			# Make sure the conditions are right
			return if game.stage isnt 'property auction'

			if not command.input
				game.say 'You must provide a bid amount.'
			else
				game.processBid player, command.input
			return

		# Only random actions can take place from here
		return if not game.canTakeAction()

		# Mortgaging
		if command.command is 'mortgage'
			if not command.input
				game.say 'You must provide the ID of the property to mortgage.'
			else
				game.processMortgage player, command.input
			return

		# Paying off mortgages
		if command.command is 'pay-mortgage'
			if not command.input
				game.say 'You must provide the ID of the property to pay off.'
			else
				game.processPayMortgage player, command.input
			return

		# Building houses
		if command.command is 'build-house'
			if not command.input
				game.say 'You must provide the ID of the property to build on.'
			else
				game.processBuildHouse player, command.input
			return

		# Building hotels
		if command.command is 'build-hotel'
			if not command.input
				game.say 'You must provide the ID of the property to build on.'
			else
				game.processBuildHotel player, command.input
			return

		# Starts a trade
		if command.command is 'sell'
			# item player price
			args = command.input.split ' '

			if args.length isnt 3
				game.say 'Expected !sell [property ID] [player] [price].'
				return

			game.processTradeInit player, args[0], args[1], args[2]
			return

		# Accepts a trade
		if command.command is 'accept'
			game.processTradeAccept player, command.input
			return

		# Declines a trade
		if command.command is 'decline'
			game.processTradeDecline player
			return

		# Pay your jail fine
		if command.command is 'payfine'
			game.processJailFine player
			return


class Game
	channel: null
	client: null
	stage: 'join'
	players: {}
	board: null
	boardGroups: {}
	chanceCards: []
	communityChestCards: []
	chanceDeck: null
	communityChestDeck: null
	tokens: ['Wheelbarrow', 'Battleship', 'Racecar', 'Thimble', 'Boot', 'Scottie dog', 'Top hat', 'Iron', 'Howitzer', 'Man on horseback']

	rotation: null
	houses: 32
	hotels: 12

	lastDice: 0

	highestBid: 0
	bidHolder: null
	bidTimeout: null

	tradeFrom: null
	tradeTo: null
	tradeProperty: null
	tradeValue: null

	# Game constructor
	constructor: (@channel, @client) ->

	# Say things to the current channel
	say: (message) =>
		@client.say @channel, message

	# Adds the given player to the game
	addPlayer: (player) =>
		@players[player.nick] = player

	# Gets the requested player
	getPlayer: (nick) =>
		return @players[nick]

	# Case-insensitive player search
	findPlayer: (search) =>
		search = search.toLowerCase()
		for own nick, player of @players
			if search is nick.toLowerCase()
				return player
		return false

	# Takes the token for the given player
	takeToken: (player, search) =>
		for token, i in @tokens
			if search.toLowerCase() is token.toLowerCase()
				player.setToken token
				@tokens.splice i, 1
				return true
		return false

	# Gets a list of all the tokens
	getTokenString: =>
		return @tokens.join ', '

	getCurrentPlayer: =>
		return @getPlayer @rotation[0]

	getCurrentPlayerLocation: =>
		return @getLocation @getCurrentPlayer().location

	# Queues up the next turn
	startNextTurn: =>
		@stage = 'preroll'

		player = @getCurrentPlayer()
		@say "It's now #{player.nick}'s turn."

		# Jail messages
		if player.jailedTurns
			player.jailedTurns++
			
			if player.jailedTurns is 1
				@say "#{player.nick} is in jail."
			else
				@say "#{player.nick} has been in jail for #{player.jailedTurns} turns."
			@say 'You can get out of jail by rolling doubles, paying your $50 fine (!payfine) or using a "Get Out of Jail Free Card" card (!jailcard).'

	# Ends this player's turn
	endTurn: =>
		@stage = 'turn over'

		# Cycle up the next player if this player didn't have doubles
		if not @getCurrentPlayer().doubles
			player = @rotation.shift()
			@rotation.push(player)

		@startNextTurn()

	# Rolls the dice for this player
	triggerTurnRoll: =>
		@stage = 'turn'

		player = @getCurrentPlayer()
		dieOne = @getDie()
		dieTwo = @getDie()
		@lastDice = dieOne + dieTwo
		@say "You rolled a #{dieOne} and a #{dieTwo} for a total of #{dieOne + dieTwo}."

		# They rolled a double
		if dieOne is dieTwo

			# Do they get out of jail?
			if player.jailedTurns
				player.jailedTurns = false
				@say 'You rolled doubles and escape jail!'
			else if player.doubles < 3
				@say 'You rolled doubles and get an extra turn!'
				player.doubles++
			else
				@say 'You have been tossed into jail for rolling 3 doubles in a row.'
				player.doubles = 0
				@movePlayerToJail player

		else
			player.doubles = 0

		# Handle jail terms
		if player.jailedTurns is 3
			@say 'This will be your third turn in jail, so you must pay your $50 fee.'
			player.removeMoney 50
			player.jailedTurns = false

		# Move the player if they're not in jail
		@movePlayer(player, dieOne + dieTwo) if not player.jailedTurns
		location = @getLocation(player.location)
		@say "You landed on #{location.toString()}." if not player.jailedTurns
		
		# If this location has a handler, do things
		if location.handler
			location.handler()
		# Otherwise, end the turn
		else
			@endTurn()
	
	# The event triggered by a player landing on a property
	locationProperty: =>
		player = @getCurrentPlayer()
		location = @getCurrentPlayerLocation()

		# Pay up
		if location.owner
			if location.owner isnt player.nick
				rent = location.getRent()
				@say "You pay #{location.owner} $#{rent} for staying on their property."
				player.removeMoney rent
				@getPlayer(location.owner).money += rent
			@endTurn()

		# Sell this property
		else
			@say "Since nobody owns #{location.getFullLabel()} you can buy it for $#{location.price} (!buy) or let the bank auction it (!auction)."
			@stage = 'sell property'

	# The event triggered by a player landing on the income tax space
	locationIncomeTax: =>
		player = @getCurrentPlayer()

		@say 'You pay $200 for income taxes.'
		player.removeMoney 200

	# The event triggered by a player landing on the luxury tax space
	locationLuxuryTax: =>
		player = @getCurrentPlayer()

		@say 'You pay a $75 luxury tax.'
		player.removeMoney 75

	# The silly corner space that sends you packing to jail
	locationGoToJail: =>
		@say 'You go straight to jail.'
		@movePlayerToJail @getCurrentPlayer

	# Chance cards
	locationChance: =>
		# Draw a chance card
		cardId = @chanceDeck.shift()
		card = @chanceCards[cardId]
		@say "You draw a Chance card and it reads \"#{card.label}\"."

		# If this isn't a jail free card, push it on the end of the deck
		if cardId isnt 6
			@chanceDeck.push cardId
		
		# If true, we need to replay landing on a space. Otherwise end the turn
		if card.handler @getCurrentPlayer()
			location = @getCurrentPlayerLocation()
			# If this location has a handler, do things
			if location.handler
				location.handler()
			# Otherwise, end the turn
			else
				@endTurn()
		else
			@endTurn()
	
	# Community Chest cards
	locationCommunityChest: =>
		# TODO
		return

	# The player wants to purchase this property
	triggerPropertyPurchase: =>
		@stage = 'turn'

		player = @getCurrentPlayer()
		location = @getCurrentPlayerLocation()

		if location.price > player.money
			@say 'You cannot afford this property.'
			return
		
		@say "You buy #{location.getFullLabel()} for $#{location.price}."
		player.removeMoney location.price
		@setOwner location, player
		@endTurn()

	# Triggers a property auction
	triggerPropertyAuction: =>
		@stage = 'property auction'

		location = @getCurrentPlayerLocation()

		@say "#{location.getFullLabel()} is now up for auction. Type !bid [amount] to make a bid for this property. The auction will close after 30 seconds of inactivity."

	# Process a bid request
	processBid: (player, amount) =>
		amount = (amount|0)

		# If this player has already bid, return their money for this process
		money = player.money
		money += @highestBid if player.nick is @bidHolder

		if amount > money
			@say 'You do not have that much money.'
			return

		if amount <= @highestBid
			@say 'Your big must be higher than the highest bid.'
			return

		# Return the old bidder's money
		if @oldBidder
			oldBidder = @getPlayer(@bidHolder)
			oldBidder.money += @highestBid

		# Take money from the new bidder
		player.removeMoney amount
		@highestBid = amount
		@bidHolder = player.nick

		# TODO: Tell the person that they are the current bid winner

		# Set the clock
		clearTimeout(@bidTimeout) if @bidTimeout
		@bidTimeout = setTimeout((=>
			@say 'Bid will close in 5 seconds if there is no more activity.'
			@bidTimeout = setTimeout((=> @closeBid()), 5000)
		), 30000)

	# Closes up a bid
	closeBid: =>
		@stage = 'turn'

		player = @getPlayer(@bidHolder)
		location = @getCurrentPlayerLocation()

		@setOwner location, player
		@say "#{player.nick} won the bid and now owns #{location.getFullLabel()}."

		@bidHolder = null
		@highestBid = 0
		@bidTimeout = null

		@endTurn()

	# Takes out a mortgage on a property
	processMortgage: (player, propertyId) =>
		location = @getLocation (propertyId|0)

		if not location or location.type isnt 'property'
			@say 'Invalid property ID.'
			return
		if location.owner isnt player.nick
			@say 'You cannot mortgage a property you do not own.'
			return
		if location.currentMortgage
			@say 'You have already taken out a mortgage on this property.'
			return
		if not @unimprovedGroup(location.group)
			@say 'You cannot mortgage a property if any properties in this group have houses or hotels.'
			return

		# Okay, they meet all of our conditions
		location.currentMortgage = location.getMortgageValue()
		player.money += location.getMortgageValue()
		@say "The bank gives you a $#{location.getMortgageValue()} mortgage against #{location.label}."

	# Allows the user to pay off a mortgage
	processPayMortgage: (player, propertyId) =>
		location = @getLocation (propertyId|0)

		if not location or location.type isnt 'property'
			@say 'Invalid property ID.'
			return
		if location.owner isnt player.nick
			@say 'You cannot mortgage a property you do not own.'
			return
		if not location.currentMortgage
			@say 'That property has no mortgage taken out.'
			return

		mortgage = location.getMortgageValue() + Math.ceil(location.getMortgageValue() * 0.10)
		if player.money < mortgage
			@say "You cannot afford to pay off the $#{mortgage} mortgage ($#{location.getMortgageValue()} + 10% interest)."
			return

		# They meet the conditions for paying this off
		location.currentMortgage = false
		player.removeMoney mortgage
		@say "You pay off the $#{mortgage} mortgage ($#{location.getMortgageValue()} + 10% interest)."

	# Builds a house on a property
	processBuildHouse: (player, propertyId) =>
		location = @getLocation (propertyId|0)

		if not location or location.type isnt 'property'
			@say 'Invalid property ID.'
			return
		if not location.isImprovable()
			@say 'This property cannot be improved.'
			return
		if location.owner isnt player.nick
			@say 'You cannot build on a property you do not own.'
			return
		if @houses is 0
			@say 'There are no more houses available. Wait until another players sells theirs.'
			return
		if location.houses is 4 or location.hotels
			@say 'You cannot build any more houses on this property.'
			return
		if not @ownsMortgageFreeGroup player, location.group
			@say 'You must own the entire color group before you can build, and all properties of the group must be mortgage free.'
			return

		# Make sure they have the cash
		if player.money < location.getHouseCost()
			@say 'You do not have enough money to build a house on this property.'
			return

		# Make sure their other properties are on this level or the previous level
		if location.houses isnt 0 and @groupMinHouses(location.group) < location.houses
			plural = if location.houses is 1 then 'house' else 'houses'
			@say "All properties in this group must have at least #{location.houses} #{plural} before another can be built here."
			return

		@say "You pay $#{location.getHouseCost()} to build a house on #{location.label}."
		player.removeMoney location.getHouseCost()
		location.houses++
		@houses--

	# Builds a hotel on this property
	processBuildHotel: (player, propertyId) =>
		location = @getLocation (propertyId|0)

		if not location or location.type isnt 'property'
			@say 'Invalid property ID.'
			return
		if not location.isImprovable()
			@say 'This property cannot be improved.'
			return
		if location.owner isnt player.nick
			@say 'You cannot build on a property you do not own.'
			return
		if @hotels is 0
			@say 'There are no more hotels available. Wait until another players sells theirs.'
			return
		if location.hotels is 1
			@say 'You cannot build anymore hotels on this property.'
			return
		if location.houses isnt 4
			@say 'You need 4 houses on this property before you can build a hotel on it.'
			return

		# Make sure they have the cash
		if player.money < location.getHotelCost()
			@say 'You do not have enough money to build a hotel on this property.'
			return

		min = @groupMinHouses(location.group)
		if min isnt 0 or min isnt 4 # We let 0 houses slide because they might have hotels at this point
			@say 'All properties in this group must have at least 4 houses before a hotel can be built here.'
			return

		@say "You pay $#{location.getHotelCost()} to build a hotel on #{location.label}."
		player.removeMoney location.getHotelCost()
		location.houses = 0
		location.hotels = 1
		@houses += 4
		@hotels--

	# Process the start of a trade
	processTradeInit: (player, propertyId, nick, amount) =>
		location = @getLocation (propertyId|0)
		otherPlayer = @findPlayer nick
		amount = (amount|0)

		if @tradeFrom
			@say 'A trade is currently in progress.'
			return
		if not location or location.type isnt 'property'
			@say 'Invalid property ID.'
			return
		if location.owner isnt player.nick
			@say 'You cannot sell a property you do not own.'
			return
		if not otherPlayer
			@say "Nobody by the name of '#{nick}' is in the game."
			return
		if player.nick is otherPlayer.nick
			@say 'You cannot trade with yourself. Get some friends.'
			return
		if not amount or amount <= 0
			@say 'You must provide a selling price greater than zero.'
			return
		if not @unimprovedGroup location.group
			@say 'You cannot sell a property if any property in the group is currently improved.'
			return

		@tradeFrom = player.nick
		@tradeTo = otherPlayer.nick
		@tradeProperty = location.id
		@tradeValue = amount
		@tradeTimeout = setTimeout @closeTrade, 30000
		@say "#{player.nick} has proposed to sell #{location.label} to #{otherPlayer.nick} for $#{amount}. Type !accept or !decline to accept or decline the trade. The trade will expire in 30 seconds."

	# Closes up after atrade
	closeTrade: (silent) =>
		if not silent
			@say "#{@tradeFrom}'s proposal to #{@tradeTo} has expired."

		clearTimeout(@tradeTimeout)
		@tradeFrom = null
		@tradeTo = null
		@tradeProperty = null
		@tradeValue = 0
		@tradeTimeout = null

	# Process accepting a trade
	processTradeAccept: (player, override) =>
		if not @tradeTo or @tradeTo isnt player.nick
			@say 'You do not have any trades to accept.'
			return

		location = @getLocation @tradeProperty
		otherPlayer = @getPlayer @tradeFrom
		payMortgage = override.toLowerCase() is 'yes'

		if amount > player.money
			@say 'You cannot afford to accept this offer.'
			return

		if location.currentMortgage and not override
			clearTimeout(@tradeTimeout)
			@say "The property has a $#{location.currentMortgage} mortgage against it. Type \"!accept [yes|no]\" to accept and pay the mortgage or to accept and not pay the mortgage."
			@tradeTimeout = setTimeout @closeTrade, 30000
			return

		cost = amount
		if location.currentMortgage
			if payMortgage
				cost += location.currentMortgage

				if cost > player.money
					@say "You cannot afford to buy this property for $#{amount} and pay the $#{location.currentMortgage} mortgage."
					return

				@say "You pay #{tradeTo} $#{amount} for the property and the bank $#{location.currentMortgage} to clear the mortgage."
				location.currentMortgage = false

			else
				# Increase the mortgage by 10% if it doesn't get paid off immediately
				@say "You pay #{tradeTo} $#{amount} for the property and the bank adds 10% to the mortgage on the property."
				location.currentMortgage += Math.ceil(location.currentMortgage * 0.10)
		else
			@say "You pay #{tradeTo} $#{amount} for the property."

		closeTrade true
		player.removeMoney cost
		otherPlayer.money += amount
		@changeOwner location, otherPlayer, player

	# Declines a trade
	processTradeDecline: (player, override) =>
		if not @tradeTo or @tradeTo isnt player.nick
			@say 'You do not have any trades to decline.'
			return

		closeTrade true
		@say "#{player.nick} has declined #{@tradeFrom}'s offer."

	# Allows a player to pay off their jail fine
	processJailFine: (player) =>
		if not player.jailedTurns
			@say 'You are not in jail.'
			return
		if player.money < 50
			@say 'You cannot afford to pay off your $50 fine.'
			return

		@say 'You pay your $50 fine and get released from jail.'
		player.jailedTurns = false
		player.removeMoney 50

	# Triggers the start of the game
	triggerStart: =>
		@stage = 'ready up'

		# if Object.keys(@players).length < 3
		# 	@client.say @channel, 'You need at least 3 players to start a game of monopoly.'
		# 	@client.say @channel, 'The current game will be aborted.'
		# 	games[@channel] = null
		# 	return

		@shuffleRotation()
		@initBoard()
		@initChance()
		@initCommunityChest()
		@say 'The game will now start. You can type !status [name] at any time to get the status of a player.'
		@say "Turns will be taken in the following order: #{@rotation.join(', ')}"
		@startNextTurn()

	# Checks to see if a player owns a whole group of properties
	ownsGroup: (player, group) =>
		for locationId in @boardGroups[group]
			location = @getLocation locationId
			if location.owner isnt player.nick
				return false
		return true

	# Counts up how much of this group this owner has
	ownedGroupCount: (player, group) =>
		count = 0
		for locationId in @boardGroups[group]
			location = @getLocation locationId
			if location.owner is player.nick
				count++
		return count

	# Checks whether or not the player owns this group and its mortgage free
	ownsMortgageFreeGroup: (player, group) =>
		for locationId in @boardGroups[group]
			location = @getLocation locationId
			if location.owner isnt player.nick or location.currentMortgage
				return false
		return true

	# Gets the smallest number of houses built on this group
	groupMinHouses: (group) =>
		min = 0
		for locationId in @boardGroups[group]
			location = @getLocation locationId
			min = location.houses if location.houses < min
		return min

	# Checks to see if all of the property in this group is unimproved
	unimprovedGroup: (group) =>
		for locationId in @boardGroups[group]
			location = @getLocation locationId
			if not location.isUnimproved()
				return false
		return true

	# Sends the player to jail without passing go
	movePlayerToJail: (player) =>
		# Jail is in the 10th bucket (11th element)
		player.location = 10
		player.jailedTurns = 0

	# Moves the player to the given location
	movePlayerTo: (player, location, skipGo) =>
		# See if we "pass" Go
		if not skipGo and location <= player.location
			@playerHitGo player, location isnt 0

		player.location = location

	# Move player
	movePlayer: (player, positions, skipGo) =>
		player.location += positions

		# Handle wrapping around the board
		if player.location >= @board.length
			player.location -= @board.length

			if not skipGo
				@playerHitGo player, player.location isnt 0

	# Gives the player money for landing on/passing go
	playerHitGo: (player, passed) =>
		player.money += 200

		if not passed
			@say 'You land on Go and collect $200.'
		else
			@say 'You pass Go and collect $200.'		

	# Sets the owner of a property
	setOwner: (location, player) =>
		location.owner = player.nick
		player.property.push location.bucket
		player.property.sort()

	# Exchanges owner of a property
	changeOwner: (location, oldPlayer, newPlayer) =>
		oldPlayer.property.splice oldPlayer.property.indexOf(location.bucket), 1
		setOwner newPlayer

	# Shuffles the player list
	shuffleRotation: =>
		@rotation = []
		for own nick, player of @players
			@rotation.push player.nick
		@rotation = utils.shuffle @rotation

	# Returns true if the user can take an arbitrary action now
	canTakeAction: =>
		return @stage isnt 'join'

	# Gets a die value
	getDie: =>
		return Math.floor(Math.random() * 6) + 1

	# Prints the status of the given player if it exists
	playerStatus: (nick) =>
		player = @findPlayer nick
		return if not player
		
		@say "Current information on #{player.nick}:"
		@say " - Money: #{player.moneyString()}"

		properties = []
		for propertyId in player.property
			location = @getLocation propertyId
			properties.push("#{location.getFullLabel()} [#{location.group}]")

		@say " - Property: #{properties.join(', ')}" if properties.length

	# Displays information on the given property
	propertyInfo: (search) =>
		location = @getLocation (search|0)

		if not location or location.type isnt 'property'
			@say 'Please provide a valid property ID.'
			return

		@say "#{location.getFullLabel()} [#{location.group}]:"
		@say " - Owner: #{if location.owner then location.owner else 'none'}"
		@say " - Price: $#{location.price}, Mortgage: $#{location.getMortgageValue()}"

		if location.owner and location.group is 'rail road'
			rent = location.getRent()
			bonus = ''
			bonus = " +$#{rent - location.getBaseRent()} for owning other rail roads" if rent - location.getBaseRent() > 0
			@say " - Rent: $#{location.getBaseRent()}#{bonus}"
		else if location.group is 'utility'
			if not location.owner or not @ownsGroup location.owner, location.group
				@say " - Rent: x4 value of dice roll"
			else
				@say " - Rent: x10 value of dice roll"
		else
			@say " - Rent: $#{location.getBaseRent()}#{if @ownsGroup(location.owner, location.group) then ' x2 (for owning the property group)' else ''}"

		@say " - Cost to Build a House: $#{location.getHouseCost()}" if location.isImprovable()
		@say " - Cost to Build a Hotel: $#{location.getHotelCost()}" if location.isImprovable()
		@say " - Houses: #{location.houses}" if location.houses
		@say " - Hotels: #{location.hotels}" if location.hotels

		@say ' - Has mortgage taken out' if location.currentMortgage

	# Determines whether or not it is this player's turn
	isTurn: (player) =>
		return player.nick is @rotation[0]

	# Gets the board location by its id
	getLocation: (location) =>
		return @board[location]

	# Initializes the game board
	initBoard: =>
		# Set up the board locations
		@board = []
		board = [
			{label: 'Go', type: 'go'} # 0

			{label: 'Mediterranean Avenue', type: 'property', group: 'brown', price: 60, rent: [2, 10, 30, 90, 160, 250]} # 1
			{label: 'Community Chest', type: 'community'}
			{label: 'Baltic Avenue', type: 'property', group: 'brown', price: 60, rent: [4, 20, 60, 180, 320, 450]}

			{label: 'Income Tax', type: 'income tax'} # 4
			{label: 'Reading Railroad', type: 'property', group: 'rail road'}

			{label: 'Oriental Avenue', type: 'property', group: 'light blue', price: 100, rent: [6, 30, 90, 270, 400, 550]} # 6
			{label: 'Chance', type: 'chance'}
			{label: 'Vermont Avenue', type: 'property', group: 'light blue', price: 100, rent: [6, 30, 90, 270, 400, 550]}
			{label: 'Connecticut Avenue', type: 'property', group: 'light blue', price: 120, rent: [8, 40, 100, 300, 450, 600]}

			{label: 'Jail', type: 'jail'} # 10

			{label: 'St. Charles Place', type: 'property', group: 'pink', price: 140, rent: [10, 50, 150, 450, 625, 750]} # 11
			{label: 'Electric Company', type: 'property', group: 'utility'}
			{label: 'States Avenue', type: 'property', group: 'pink', price: 140, rent: [10, 50, 150, 450, 625, 750]}
			{label: 'Virginia Avenue', type: 'property', group: 'pink', price: 160, rent: [12, 60, 180, 500, 700, 900]}

			{label: 'Pennsylvania Railroad', type: 'property', group: 'rail road'} # 15

			{label: 'St. James Place', type: 'property', group: 'orange', price: 180, rent: [14, 70, 200, 550, 750, 950]} # 16
			{label: 'Community Chest', type: 'community'}
			{label: 'Tennessee Avenue', type: 'property', group: 'orange', price: 180, rent: [14, 70, 200, 550, 750, 950]}
			{label: 'New York Avenue', type: 'property', group: 'orange', price: 200, rent: [16, 80, 220, 600, 800, 1000]}

			{label: 'Free Parking', type: 'parking'} # 20

			{label: 'Kentucky Avenue', type: 'property', group: 'red', price: 220, rent: [18, 90, 250, 700, 875, 1050]} # 21
			{label: 'Chance', type: 'chance'}
			{label: 'Indiana Avenue', type: 'property', group: 'red', price: 220, rent: [18, 90, 250, 700, 875, 1050]}
			{label: 'Illinois Avenue', type: 'property', group: 'red', price: 240, rent: [20, 100, 300, 750, 925, 1100]}

			{label: 'B&O Railroad', type: 'property', group: 'rail road'} # 25

			{label: 'Atlantic Avenue', type: 'property', group: 'yellow', price: 260, rent: [22, 110, 330, 800, 975, 1150]} # 26
			{label: 'Ventnor Avenue', type: 'property', group: 'yellow', price: 260, rent: [22, 110, 330, 800, 975, 1150]}
			{label: 'Water Works', type: 'property', group: 'utility'}
			{label: 'Marvin Gardens', type: 'property', group: 'yellow', price: 280, rent: [24, 120, 360, 850, 1025, 1200]}

			{label: 'Go to Jail', type: 'go to jail'} # 30

			{label: 'Pacific Avenue', type: 'property', group: 'green', price: 300, rent: [26, 130, 390, 900, 1100, 1275]} # 31
			{label: 'North Carolina Avenue', type: 'property', group: 'green', price: 300, rent: [26, 130, 390, 900, 1100, 1275]}
			{label: 'Community Chest', type: 'community'}
			{label: 'Pennsylvania Avenue', type: 'property', group: 'green', price: 320, rent: [28, 150, 450, 1000, 1200, 1400]}

			{label: 'Short Line', type: 'property', group: 'rail road'} # 35
			{label: 'Chance', type: 'chance'}

			{label: 'Park Place', type: 'property', group: 'blue', price: 350, rent: [35, 175, 500, 1100, 1300, 1500]} # 37
			{label: 'Luxury Tax', type: 'luxury tax'}
			{label: 'Boardwalk', type: 'property', group: 'blue', price: 400, rent: [50, 200, 600, 1400, 1700, 2000]}
		]

		i = 0
		for data in board
			location = new BoardLocation(@, i, data.label, data.type, data.group)
			i++

			if data.price
				location.price = data.price
			if data.rent
				location.rent = data.rent
			if data.group
				if not @boardGroups[data.group]
					@boardGroups[data.group] = []
				@boardGroups[data.group].push(location.bucket)

			if data.group is 'rail road'
				location.price = 200
			else if data.group is 'utility'
				location.price = 150

			# Register location events
			if data.type is 'property'
				location.handler = @locationProperty
			else if data.type is 'income tax'
				location.handler = @locationIncomeTax
			else if data.type is 'luxury tax'
				location.handler = @locationLuxuryTax
			else if data.type is 'go to jail'
				location.handler = @locationGoToJail
			# else if data.type is 'chance'
			# 	location.handler = @locationChance
			# else if data.type is 'community'
			# 	location.handler = @locationCommunityChest

			@board.push(location)

	# Creates and shuffles the deck of chance cards
	initChance: =>
		@chanceCards = [
			{
				text: 'Advance to Go'
				handler: (player) =>
					@movePlayerTo player, 0
					return false
			}
			{
				text: 'Advance to Illinois Ave.'
				handler: (player) =>
					@movePlayerTo player, 24
					return true
			}
			{
				text: 'Advance to St. Charles Place'
				handler: (player) =>
					@movePlayerTo player, 11
					return true
			}
			{
				text: 'Advance token to nearest Utility'
				handler: (player) =>
					if player.location >= 12
						@movePlayerTo player, 28
					else
						@movePlayerTo player, 12
					return true
			}
			{
				text: 'Advance token to nearest Railroad'
				handler: (player) =>
					# TODO: Pay double?
					if player.location >= 35 or player.locaton < 5 # Reading railroad
						@movePlayerTo player, 5
					else if player.location < 15
						@movePlayerTo player, 15
					else if player.location < 25
						@movePlayerTo player, 25
					else if player.location < 35
						@movePlayerTo player, 35
					return true
			}
			{
				text: 'Bank pays you dividend of $50'
				handler: (player) =>
					player.money += 50
					return false
			}
			{
				text: 'Get ouf of Jail Free'
				handler: (player) =>
					player.jailCardChance = true
					return false
			}
			{
				text: 'Go back 3 spaces'
				handler: (player) =>
					# Chance cards will never be drawn less than 3 spaces from Go, so don't worry about wrapping
					player.location -= 3
					return true
			}
			{
				text: 'Go to Jail'
				handler: (player) =>
					@movePlayerToJail player
					return false
			}
			{
				text: 'Make general repairs on all your property ($25 per house, $100 per hotel)'
				handler: (player) =>
					amount = 25 * player.getHouseCount()
					amount += 100 * player.getHotelCount()
					player.removeMoney amount
					return false
			}
			{
				text: 'Pay poor tax of $15'
				handler: (player) =>
					player.removeMoney 15
					return false
			}
			{
				text: 'Take a trip to Reading Railroad'
				handler: (player) =>
					@movePlayerTo player, 5
					return true
			}
			{
				text: 'Take a walk on the Boardwalk'
				handler: (player) =>
					@movePlayerTo player, 39
					return true
			}
			{
				text: 'You have been elected Chairman of the Board - Pay each player $50'
				handler: (player) =>
					for otherPlayer in @players
						if otherPlayer.nick isnt player.nick
							player.removeMoney 50, otherPlayer
							if player.bankrupt
								return false
							otherPlayer.money += 50
					return false
			}
			{
				text: 'Your building loan matures - Collect $150'
				handler: (player) =>
					player.money += 150
					return false
			}
		]

		@chanceDeck = utils.shuffle [0..@chanceCards.length-1]

	# Creates and shuffles the deck of community chest cards
	initCommunityChest: =>
		@communityChestCards = [
			{
				label: ''
				handler: (player) =>
					
			}
			{
				label: ''
				handler: (player) =>

			}
		]

		@communityChestDeck = utils.shuffle [0..@communityChestCards.length-1]


class Player
	game: null
	nick: null
	token: null

	money: 1500
	bankrupt: false
	location: 0
	jailedTurns: false
	property: []
	doubles: 0
	jailCardChance: false
	jailCardCommunity: false

	# Player constructor
	constructor: (@game, @nick) ->

	# Sets this player's game token
	setToken: (token) =>
		@token = token

	# Gets the formatted money string of this player
	moneyString: =>
		return '$' + @money.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",")

	# Counts the number of houses this player has
	getHouseCount: =>
		houses = 0
		for propertyId in property
			location = game.getLocation propertyId
			houses += location.houses
		return houses

	# Counts the number of hotels this player has
	getHotelCount: =>
		hotels = 0
		for propertyId in property
			location = game.getLocation propertyId
			hotels += location.hotels
		return hotels

	# Removes money and triggers bankruptcy if neccessary
	removeMoney: (amount, otherPlayer) =>
		@money -= amount

		# TODO: Handle banktruptcy


class BoardLocation
	game: null
	bucket: null
	type: null
	group: null
	label: null
	price: null
	rent: [] # 0 - empty, 1-4 = with n houses, 5 = with hotel
	handler: null

	owner: null
	houses: 0
	hotels: 0
	currentMortgage: false

	constructor: (@game, @bucket, @label, @type, @group) ->

	isUnimproved: =>
		return @houses is 0 and @hotels is 0

	getMortgageValue: =>
		return @price / 2

	isImprovable: =>
		return @type is 'property' and @group isnt 'utility' and @group isnt 'rail road'

	# Gets the cost to build a house on this property
	getHouseCost: =>
		# Front side: $50
		if @bucket < 10
			return 50

		# Left side: $100
		else if @bucket < 20
			return 100

		# Top side: $150
		else if @bucket < 30
			return 150

		# Right side: $200
		return 200

	# Gets the cost to build a hotel on this property
	getHotelCost: =>
		return @getHouseCost()

	# The total rent
	getRent: =>
		rent = @getBaseRent()
		return rent if not rent # Bail out early if we have nothing to modify

		# Special conditions
		if @owner
			# If this is a railroad, give them a bonus
			if @group is 'rail road'
				rent *= Math.pow 2, (@game.ownedGroupCount(@owner, @group) - 1)

			# If this person owns both utilities, they get x2.5 rent (x10 instead of x4 roll)
			else if @group is 'utility' and @game.ownsGroup @owner, @group
				rent *= 2.5

			# If this person owns the whole group, they get double rent
			else if @game.ownsGroup @owner, @group
				rent *= 2

		return rent

	# Calculates the base rent of this property
	getBaseRent: =>
		# Only owned properties without mortgages can charge rent
		if not @owner or @currentMortgage
			return 0

		if @rent
			if @hotels
				return @rent[5]
			else if @houses
				return @rent[@houses]
			else
				return @rent[0]

		if @group is 'rail road'
			return 25

		if @group is 'utility'
			return 4 * game.lastDice

	getFullLabel: =>
		result = @label
		result += " (ID: #{@bucket})" if @type is 'property'
		return result

	# Creates a string representation of this location
	toString: =>
		result = @getFullLabel()
		result += " [#{@group}]" if @group
		result += " owned by #{@owner}" if @owner

		return result