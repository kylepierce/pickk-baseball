Match = require "mtr-match"
_ = require "underscore"

module.exports = class
  constructor: (data) ->
    Match.check data, Object

    @_id = data['playerId']
    @playerId = data['playerId']
    @name = data['firstName'] + " " + data['lastName']
    @firstName = data['firstName']
    @lastName = data['lastName']
    @team = data['team']['teamId']
    @position = data['positions'][0]['name']

    now = new Date()
    @updatedAt = now

  getSelector: ->
    "_id": @_id
