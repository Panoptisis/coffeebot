###
 IRC Bot
  - Logging
###

# Interal functions
lpad = (str, pad, len) ->
	str = '' + str
	while str.length < len
		str = pad + str
	return str

ddpad = (str) ->
	return lpad str, '0', 2

# Prints a pretty log message with a timestamo
exports.log = (message) ->
	date = new Date
	stamp = ddpad(date.getHours()) + ':' + ddpad(date.getMinutes()) + ':' + ddpad(date.getSeconds())

	console.log "[#{stamp}] #{message}"
