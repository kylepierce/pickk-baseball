Match = require "mtr-match"
_ = require "underscore"

module.exports = class
  constructor: (data) ->
    Match.check data, Object

    @_id = data['id']
    @playerId = data['id']
    @name = data['full_name']
    @firstName = data['first_name']
    @lastName = data['last_name']
    @team = data['team_id']
    @position = data['position']

    now = new Date()
    @updatedAt = now

  getSelector: ->
    "_id": @_id
