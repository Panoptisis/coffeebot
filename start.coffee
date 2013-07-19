
# Grab includes
bot = require('./init').client
modules = require('./modules').loader

# Attach modules
modules bot, [
		'test'
		'admin-controls'
		'simple-games'
		'vote'
	]