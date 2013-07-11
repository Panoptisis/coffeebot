###
 IRC Bot
  - Allows for module loading
###

# Loads modules by name
moduleLoader = (client, modules) ->

	for module in modules
		module = require("./modules/#{module}")
		for own name,func of module
			func(client)

# Export the function
exports.loader = moduleLoader