Match = require "mtr-match"
_ = require "underscore"
moment = require "moment"

module.exports = class
  constructor: (data) ->
    Match.check data, Object

    _.extend @, data

    @scheduled = moment(@scheduled).toDate()
    @live = @status is 'inprogress'
    @commercial = false

  getSelector: ->
    "id": @id
