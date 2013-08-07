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

exports.replace = (str, messages) ->
	for own name,value of messages
		find = new RegExp('{{' + name + '}}', 'g')
		str = str.replace(find, value)
	return str

exports.shuffle = (a) ->
	i = a.length
	while --i > 0
		j = ~~(Math.random() * (i + 1))
		t = a[j]
		a[j] = a[i]
		a[i] = t
	a
