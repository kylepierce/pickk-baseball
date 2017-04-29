Match = require "mtr-match"
_ = require "underscore"
moment = require "moment"

module.exports = class
  constructor: (data) ->
    Match.check data, Object
    @_id = data['teamId']
    @nickname = data['nickname']
    @fullName = "#{data['location']} #{data['nickname']}"
    @computerName = data['abbreviation'].toLowerCase()
    @city = data['location']
    @state = data['venue']['state']['abbreviation']

    now = new Date()
    @updatedAt = now

  getSelector: ->
    "_id": @_id
