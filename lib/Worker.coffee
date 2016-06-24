_ = require "underscore"
Promise = require "bluebird"
stream = require "readable-stream"
Match = require "mtr-match"

module.exports = class
  constructor: (options, dependencies) ->
    Match.check options,
      name: String
      maxLoops: Match.Optional(Match.Integer)
      delay: Match.Integer
      taskClass: Function

    _.extend @, options

    @iteration = 0 if @maxLoops

    Match.check dependencies, Match.ObjectIncluding
      mongodb: Match.Any
      logger: Match.Any

    @logger = dependencies.logger
    @dependencies = dependencies

  start: ->
    @instance = new @taskClass @dependencies
    @logger.info "Start worker \"#{@name}\""
    new Promise (resolve, reject) =>
      @loop(resolve, reject)
    .bind @
    .catch (error) ->
      @logger.error "En error occurred for worker \"#{@name}\"", error
    .finally -> @logger.info "Finish worker \"#{@name}\""

  loop: (resolve, reject) ->
    Promise.bind @
    .then -> @iteration++
    .tap -> @logger.verbose "Start iteration #{@iteration}"
    .then -> @instance.execute()
    .then ->
      if @maxLoops and (@iteration is @maxLoops)
        resolve()
      else
        setTimeout((=> process.nextTick(@loop.bind(@), resolve, reject)),
        @delay)
    .catch reject
