Match = require "mtr-match"
_ = require "underscore"
moment = require "moment"
sid = require "shortid"

module.exports = class
  constructor: (data) ->
    Match.check data, Object

    _.extend @, data

    away = @['teams'][0]
    home = @['teams'][1]

    # @_id = @id
    @id =  @['eventId']
    @home = home
    @home_team = home.teamId
    @away = away
    @away_team = away.teamId
    @scheduled =  moment(@['startDate'][1]['full']).toDate()
    @iso = new Date(@['startDate'][1]['full']).toISOString()
    @name = "#{home.nickname} vs #{away.nickname}"
    @gameDate = moment.utc(@scheduled).format('MMM Do LT')
    @sport = "MLB"
    @period = @['eventStatus']['inning']
    @live = @['eventStatus']['name'] is "In-Progress"
    @status = @['eventStatus']['name']
    @completed = @status in ['complete', 'closed']

  getSelector: ->
    "eventId": @['eventId']
