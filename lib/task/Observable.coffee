Match = require "mtr-match"
Promise = require "bluebird"

module.exports = class
  constructor: ->
    @registeredEvents = []
    @listeners = {}
  
  # should be override by derived class to support specific events
  registerEvents: (events) ->
    Match.check events, Array
    @registeredEvents = events

  checkEvent: (event) ->
    Match.check event, String
    throw new Error("Event '#{event}' is not supported. Use one of [#{@registeredEvents.join()}]") if event not in @registeredEvents

  emit: (event, data) ->
    Match.check event, String
    
    @checkEvent event
    listeners = @listeners[event] or []
    Promise.all(listener(data) for listener in listeners)

  observe: (event, callback) ->
    Match.check event, String
    Match.check callback, Function

    @checkEvent event
    @listeners[event] ?= []
    @listeners[event].push callback
