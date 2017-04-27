Match = require "mtr-match"
_ = require "underscore"
moment = require "moment"

module.exports = class
  constructor: (data) ->
    Match.check data, Object

    _.extend @, data

    away = @['teams'][0]
    home = @['teams'][1]

    @_id = @['eventId']
    @home = home
    @away = away
    @scheduled = moment(@['startDate'][1]['full']).toDate()
    @name = "#{home.nickname} vs #{away.nickname}"
    @gameDate = moment.utc(@scheduled).format('MMM Do LT')
    @sport = "MLB"
    # @tv = @['tvStations']['callLetters']
    @dateCreated = moment.utc(@scheduled).startOf('day').toDate()
    @live = @['eventStatus']['name'] is "In-Progress"
    @completed = @status in ['complete', 'closed']

  getSelector: ->
    "_id": @_id
