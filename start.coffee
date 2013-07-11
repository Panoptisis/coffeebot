
# Grab includes
bot = require('./init').client
modules = require('./modules').loader

# Attach modules
modules bot, [
		'test'
		'chat'
		'admin-controls'
		'simple-games'
	]