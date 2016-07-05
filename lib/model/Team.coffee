Match = require "mtr-match"
_ = require "underscore"
moment = require "moment"

module.exports = class
  constructor: (data) ->
    Match.check data, Object

    @_id = data['id']
    @nickname = data['name']
    @fullName = "#{data['market']} #{data['name']}"
    @computerName = data['abbr'].toLowerCase()
    @city = data['market']
    @state = ""

  getSelector: ->
    "_id": @_id
