Match = require "mtr-match"
_ = require "underscore"

module.exports = class
  constructor: (data) ->
    Match.check data, Object

    @_id = data['player_id']
    @playerId = data['player_id']
    @name = "#{data['first_name']} #{data['last_name']}"
    @team = data['team_id']
    @position = data['position']

  getSelector: ->
    "_id": @_id
