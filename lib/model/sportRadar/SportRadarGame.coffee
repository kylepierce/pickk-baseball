Match = require "mtr-match"
_ = require "underscore"
moment = require "moment"

module.exports = class
  constructor: (data) ->
    Match.check data, Object

    _.extend @, data

    away = @['teams'][1]
    home = @['teams'][0]

    @id =  @['eventId']
    # @commercial = false
    @home = home
    @home_team = home.teamId
    @away = away
    @away_team = away.teamId
    @scheduled = moment(@['startDate'][1]['full']).toDate()
    @iso =  new Date(@['startDate'][1]['full']).toISOString()
    @name = "#{home.nickname} vs #{away.nickname}"
    @sport = "MLB"
    @period = 0
    @live = @['eventStatus']['name'] is "In-Progress"
    @status = @['eventStatus']['name']
    @completed = @status in ['Complete', 'Closed']

  getSelector: ->
    "eventId": @['eventId']
