Match = require "mtr-match"
_ = require "underscore"
moment = require "moment"

module.exports = class
  constructor: (data) ->
    Match.check data, Object

    _.extend @, data

    home = @['home'] or @['scoring']['home']
    away = @['away'] or @['scoring']['away']

    @_id = @id
    @scheduled = moment(@scheduled).toDate()
    @name = "#{home['name']} vs #{away['name']}"
    @gameDate = moment.utc(@scheduled).format('MMM Do LT')
    @tv = @['broadcast']['network']
    @dateCreated = moment.utc(@scheduled).startOf('day').toDate()
    @live = @status is 'inprogress'
    @completed = @status is 'closed'

  getSelector: ->
    "_id": @_id
