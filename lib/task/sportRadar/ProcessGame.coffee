_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Task = require "../Task"
SportRadarGame = require "../../model/sportRadar/SportRadarGame"
Team = require "../../model/Team"
Player = require "../../model/Player"
GameParser = require "./helper/GameParser"
moment = require "moment"
promiseRetry = require 'promise-retry'
chance = new (require 'chance')

module.exports = class extends Task
  constructor: (dependencies) ->
    super

    Match.check dependencies, Match.ObjectIncluding
      mongodb: Match.Any

    @logger = @dependencies.logger
    @SportRadarGames = dependencies.mongodb.collection("games")
    @Teams = dependencies.mongodb.collection("teams")
    @Players = dependencies.mongodb.collection("players")
    @Questions = dependencies.mongodb.collection("questions")
    @AtBats = dependencies.mongodb.collection("atBat")
    @Answers = dependencies.mongodb.collection("answers")
    @GamePlayed = dependencies.mongodb.collection("gamePlayed")
    @Users = dependencies.mongodb.collection("users")
    @Notifications = dependencies.mongodb.collection("notifications")
    @gameParser = new GameParser dependencies

  execute: (old, update) ->
    promiseRetry (retry) =>
      Promise.bind @
      # .then -> @checkGameStatus old, update
      .then -> @handleGame old, update
      .return true
      .catch (error) =>
        @logger.error error.message, _.extend({stack: error.stack}, error.details)
        retry(error)

  handleGame: (old, update) ->
    result = @gameParser.getPlay update

    if result
      Promise.bind @
      # .then -> @enrichGame old, result
      .then -> @detectChange old, result
      # .then -> @handleAtBat game, result
      # .then -> @handleCommercialBreak game, result
      # .then -> @resolveCommercialQuestions game, result
      # .then -> @processClosingState game, result

  enrichGame: (old, update) ->
    if !old['old']
      @SportRadarGames.update {_id: update.eventId}, {$set: update}

  detectChange: (old, update) ->
    oldStuff = old['old']['eventStatus']
    newStuff = update['eventStatus']
    list = ["strikes", "balls", "outs", "currentBatter", "eventStatusId", "innings", "inningDivision"]

    @oldPitch = old["old"]['lastCount'].length
    @newPitch = update["old"]['lastCount'].length
    pitchDiff = @newPitch - @oldPitch

    diff = []
    _.map list, (key) ->
      compare = _.isEqual oldStuff[key], newStuff[key]
      if not compare
        diff.push key

    if diff.length > 0
      if (diff.indexOf "balls") > -1|| (diff.indexOf "strikes") > -1 || pitchDiff isnt 0
        @logger.verbose "Increase in Count!"
        @createPitch old, update, diff

      if (diff.indexOf "currentBatter") > -1 || (diff.indexOf "outs") > -1
        @logger.verbose "Batter changed!"
        @createAtBat old, update, diff

      # if (diff.indexOf "innings") > -1 || (diff.indexOf "inningDivision") > -1
      #   @logger.verbose "Doing stuff"
      #   #Set the comerical status to true and create a new time + 2 minutes
      #   @handleCommercialBreak old, update

  checkGameStatus: (old, update) ->
    if update['eventStatus']['eventStatusId'] isnt 2
      #This should be a method!
      update['status'] = "completed"
      update['close_processed'] = true
      update['live'] = false
      @SportRadarGames.update {_id: update.eventId}, {$set: update}

  processClosingState: (game) ->
    return if game.close_processed isnt false

    @logger.info "Process closing game (#{game.name})"

    Promise.bind @
    .then -> @exchangeCoins game
    .then -> @awardLeaders game
    .then -> @SportRadarGames.update {_id: game._id}, {$set: {close_processed: true}}

  exchangeCoins: (game) ->
    Promise.bind @
    .then -> @GamePlayed.find {gameId: game._id}
    .map (player) ->
      notificationId = chance.guid()
      rate = if player['coins'] < 10000 then 2500 else 7500
      {coins} = player
      diamonds = Math.floor(coins / rate)
      message = "You traded #{coins} coins you earned playing #{game.name} for #{diamonds} diamonds"

      Promise.bind @
      .then ->
        @GamePlayed.update {userId: player['userId'], gameId: game._id}, {$inc: {diamonds: diamonds}}
      .then ->
        @Notifications.insert
          _id: notificationId
          userId: player['userId']
          type: "diamonds"
          source: "Exchange"
          gameId: game._id
          read: false
          notificationId: notificationId
          dateCreated: new Date()
          message: message
      # .tap -> @logger.verbose "Exchange coins on diamonds (#{diamonds})", {userId: player['userId'], gameId: game._id}

  awardLeaders: (game) ->
    rewards = [50, 40, 30, 25, 22, 20, 17, 15, 12, 10]
    positions = [1..10]
    images = {1: "1st", 2: "2nd", 3: "3rd"}
    places = {1: "First", 2: "Second", 3: "Third"}
    trophyId = "xNMMTjKRrqccnPHiZ"

    Promise.bind @
    .then -> @GamePlayed.find({gameId: game._id}).sort({coins: -1}).limit(10)
    .then (players) ->
      winners = _.zip players, rewards, positions
      winners = winners.slice 0, players.length # in case when there are less than 10 players involved
      Promise.all (for winner in winners
        do (winner) =>
          [player, reward, position] = winner

          notificationTrophyId = chance.guid()
          notificationId = chance.guid()
          now = new Date()

          notifications = []

          notifications.push
            _id: notificationTrophyId
            userId: player['userId']
            type: "trophy"
            gameId: game._id
            notificationId: notificationTrophyId
            dateCreated: now

          if position <= 3
            notifications.push
              _id: notificationId
              userId: player['userId']
              type: "diamonds"
              tag: "leader"
              gameId: game._id
              read: false
              notificationId: notificationId
              dateCreated: now
              message: "<img style='max-width:100%;' src='/#{images[position]}.png'> <br>Congrats On Winning #{places[position]} Place Here is #{reward} Diamonds!"

          Promise.bind @
          .then ->
            @GamePlayed.update {userId: player['userId'], gameId: game._id}, {$inc: {diamonds: reward}}
          .then ->
            @Users.update {_id: player['userId']},
              $push:
                "profile.trophies": trophyId
          .then -> Promise.all (@Notifications.insert notification for notification in notifications)
          # .tap -> @logger.verbose "Reward user #{player['userId']} with #{reward} diamonds for position #{position} in game (#{game.name})"
      )

  handleCommercialBreak: (game, result) ->
    # @logger.verbose "Commercial break is active"
    # it's time to start commercial break
    # It's necessary to check commercialStartedAt is undefined so it means
    # that "commercial" hasn't been unset because of timeout
    if not game.commercial and not game.commercialStartedAt
      Promise.bind @
      .then -> @SportRadarGames.update {_id: game._id}, {$set: {commercial: true, commercialStartedAt: new Date()}}
      .tap -> @logger.info "Commercial flag has been set for game (#{game.name})"
      # .tap -> @logger.verbose "Commercial flag has been set for game (#{game.name})", {gameId: game._id}
      .then -> @createCommercialQuestions game, result
    else
      # so here a commercial break is active and commercialStartedAt is set
      # It's necessary to calculate if time interval for a break is finished or not
      now = moment()
      timeout = now.diff(game.commercialStartedAt, 'minute')
      # @logger.verbose "Commercial interval for game (#{game.name}) [#{game._id}] is #{timeout} minutes", {commercialStartedAt: game.commercialStartedAt, now: now.toDate()}
      if timeout >= @dependencies.settings['common']['commercialTime']
        Promise.bind @
        .then -> @SportRadarGames.update {_id: game._id}, {$set: {commercial: false}} # do NOT unset "commercialStartedAt" here!
        .tap -> @logger.info "Commercial flag has been clear for game (#{game.name}) because of timeout"
        # .tap -> @logger.verbose "Commercial flag has been clear for game (#{game.name}) because of timeout", {gameId: game._id}
        .then -> @closeActiveCommercialQuestions game
      # the game is in progress. Clear "commercial" flag if it's been set earlier.
      else if game.commercial or game.commercialStartedAt
        Promise.bind @
        .then -> @SportRadarGames.update {_id: game._id}, {$set: {commercial: false}, $unset: {commercialStartedAt: 1}}
        .tap -> @logger.info "Commercial flag has been clear for game (#{game.name})"
        # .tap -> @logger.verbose "Commercial flag has been clear for game (#{game.name})", {gameId: game._id}
        .then -> @closeActiveCommercialQuestions game

  createCommercialQuestions: (game, result) ->

    templates = [
      title: "Hit a Single"
      # outcomes: ["aS", "aSAD2", "aSAD3", "aSAD4"]
      outcomes: [1, 2, 3, 4, 5, 6, 122]
    ,
      title: "Hit a Double"
      # outcomes: ["aD", "aDAD3", "aDAD4"]
      outcomes: [7, 8, 9, 10, 11, 123]
    ,
      title: "Hit a Triple"
      # outcomes: ["aT", "aTAD4"]
      outcomes: [12, 13, 124]
    ,
      title: "Hit a Home Run"
      # outcomes: ["aHR"]
      outcomes: [15, 16, 17, 18]
    ,
      title: "Steal a Base"
      # outcomes: ["SB2", "SB3", "SB4"]
      outcomes: [15, 16, 17, 18]
    ,
      title: "Get Hit by a Pitch"
      # outcomes: ["aHBP"]
      outcomes: ["61"]
    ]

    team = _.findWhere _.values(result.teams), {id: result.onPitchTeamId}

    Promise.bind @
    .return team
    .then (team) ->
      name = team.name
      templates = _.sample templates, 2
      Promise.all (for template in templates
        do (template) =>
          text = "Will #{name} #{template.title} in the #{inningNumber} inning?"

          options =
            option1: {title: "True"}
            option2: {title: "False"}

          Promise.bind @
          .then ->
            @Questions.insert
              _id: @Questions.db.ObjectId().toString()
              que: text
              type: "freePickk"
              game_id: game._id
              gameId: game._id
              teamId: team.id
              inning: inningNumber
              dateCreated: new Date()
              active: true
              processed: false
              commercial: true
              binaryChoice: true
              options: options
              outcomes: template.outcomes
              usersAnswered: []
          .tap ->
            @logger.info "Create commercial question '#{text}' for the game (#{game.name})"
            # @logger.verbose "Create commercial question '#{text}' for the game (#{game.name})", {gameId: game._id}
      )

  closeActiveCommercialQuestions: (game) ->
    Promise.bind @
    .then -> @Questions.find {commercial: true, game_id: game.id, active: true}
    .map (question) ->
      Promise.bind @
      .then -> @Questions.update {_id: question._id}, {$set: {active: false}}
      .tap ->
        @logger.info "Close commercial question '#{question['que']}' for the game (#{game.name})"
        # @logger.verbose "Close commercial question '#{question['que']}' for the game (#{game.name})", {gameId: game._id, id: question._id}

  resolveCommercialQuestions: (game, result) ->
    teamOutcomesList = result.outcomesList

    Promise.bind @
    .then -> @Questions.find {commercial: true, game_id: game.id, active: false, processed: false}
    .map (question) ->
      # @logger.verbose "Handle commercial question #{question.que}"
      inning = question['inning']

      outcomesList = teamOutcomesList[question['teamId']]
      if outcomesList.length >= (inning + 1)
        result = _.intersection(outcomesList[inning], question['outcomes']).length > 0
        # @logger.verbose "Try to resolve the commercial question #{question.que}", {expected: question['outcomes'], actual: outcomesList[inning], result: result}
        if result
          Promise.bind @
          .then -> @Questions.update {_id: question._id}, $set: {processed: true, outcome: true}
          .tap ->
            @logger.info "Close commercial question '#{question['que']}' for the game (#{game.name}) with true result"
            # @logger.verbose "Close commercial question '#{question['que']}' for the game (#{game.name}) with true result", {gameId: game._id}
          .then -> @rewardForCommercialQuestion game, question
        else if outcomesList.length > (inning + 1)
          Promise.bind @
          .then -> @Questions.update {_id: question._id}, $set: {processed: true, outcome: result}
          .tap ->
            @logger.info "Close commercial question '#{question['que']}' for the game (#{game.name}) with #{result} result"
            # @logger.verbose "Close commercial question '#{question['que']}' for the game (#{game.name}) with #{result} result", {gameId: game._id, result: result}
          .then -> @rewardForCommercialQuestion game, question
        else
          # @logger.verbose "Unable to close commercial question '#{question['que']}' for the game (#{game.name}) because number of innings (#{outcomesList.length}) and current (#{inning + 1})", {gameId: game._id, result: result}
      else
        # @logger.verbose "Unable to close commercial question '#{question['que']}' for the game (#{game.name}) because number of innings (#{outcomesList.length}) and current (#{inning + 1})", {gameId: game._id, result: result}

  rewardForCommercialQuestion: (game, object) ->
    options = {}
    options[true] = "option1"
    options[false] = "option2"

    Promise.bind @
    .then -> @Questions.findOne {_id: object._id}
    .then (question) ->
      outcome = options[question.outcome]

      Promise.bind @
      .then -> @Answers.update {questionId: question._id, answered: {$ne: outcome}}, {$set: {outcome: "loose"}}, {multi: true}
      # .tap (result) -> @logger.verbose "There are (#{result.n}) negative answer(s) for question (#{question['que']})"
      .then -> @Answers.find {questionId: question._id, answered: outcome}
      .tap (answers) -> @logger.info "There are (#{answers.length}) positive answer(s) for question (#{question['que']})"
      .map (answer) ->
        reward = @dependencies.settings['common']['commercialReward']
        Promise.bind @
        .then -> @Answers.update {_id: answer._id}, {$set: {outcome: "win"}}
        .then -> @GamePlayed.update {userId: answer['userId'], gameId: game.id}, {$inc: {coins: reward}}
        .then ->
          notificationId = chance.guid()
          @Notifications.insert
            _id: notificationId
            userId: answer['userId']
            gameId: game.id
            type: "coins"
            value: reward
            read: false
            notificationId: notificationId
            dateCreated: new Date()
            message: "Nice Pickk! You got #{reward} Coins!"
            sharable: false
            shareMessage: ""
        # .tap -> @logger.verbose "Reward user (#{answer['userId']}) with coins (#{reward}) for question (#{question['que']})"

  createAtBat: (old, update, diff) ->
    player = update['eventStatus']['currentBatter']
    playerId = player['playerId']
    atBatId = old['_id'] + "-" + update['eventStatus']['inning'] + "-" + update['old']["eventCount"] + "-" + playerId
    # bases = update['old']['eventStatus']['runnersOnBase']
    question = "End of #{player['firstName']} #{player['lastName']}'s at bat."

    if (diff.indexOf 'inningDivision') > -1
      createDate = moment().add 2, "minutes"
    else
      createDate = new Date()

    Promise.bind @
    .then -> @getGenericMultipliersForPlay() #bases, playerId
    .then (multipliers) ->
      options =
        option1: {title: "Out", number: 1, multiplier: multipliers['out'] }
        option2: {title: "Walk", number: 2, multiplier: multipliers['walk'] }
        option3: {title: "Single", number: 3, multiplier: multipliers['single'] }
        option4: {title: "Double", number: 4, multiplier: multipliers['double'] }
        option5: {title: "Triple", number: 5, multiplier: multipliers['triple'] }
        option6: {title: "Home Run", number: 6, multiplier: multipliers['homerun'] }

      Promise.bind @
      .then -> @closeInactiveAtBats old, atBatId
      .then -> @Questions.count {commercial: false, game_id: old["_id"], player_id: playerId, atBatQuestion: true, atBatId: atBatId}
      .then (found) ->
        if not found
          Promise.bind @
          .then ->
            @Questions.insert
              _id: @Questions.db.ObjectId().toString()
              dateCreated: createDate
              gameId: old["_id"]
              playerId: playerId
              game_id: old["_id"]
              player_id: playerId
              atBatQuestion: true
              inning: update['old']['inning']
              eventCount: update['old']['eventCount']
              period: 0
              type: "atBat"
              active: true
              background: "background: linear-gradient(rgba(34, 44, 49, .0), rgba(34, 44, 49, .5)), url('/bball2.png'); height: 75px; background-position-x: 46%; background-position-y: 100%; "
              commercial: false
              que: question
              options: options
              usersAnswered: []
          .tap (result) ->
            questionId = result.upserted?[0]?._id
            # @logger.verbose "Create play question (#{question})", {gameId: result['gameId'], playerId: playerId, play: play, questionId: questionId}

  closeInactiveAtBats: (update, atBatId) ->
    playNumber = atBatId

    Promise.bind @
    .then -> @Questions.find {commercial: false, gameId: update['_id'], active: true, atBatQuestion: true, atBatId: {$ne: atBatId}}
    .map (question) ->
      atBatId = question['atBatId']
      inning = update['inning']
      eventCount = update['eventCount']
      playerId = update['playerId']

      halfs = @gameParser.loopHalfs inning
      totalEvents = @gameParser.getEvents halfs
      atBats = @gameParser.getAtBats totalEvents
      atBat = atBats[eventCount]
      if atBat
        matchesBatter = atBat['batter']['playerId'] is playerId

      if atBat and matchesBatter
        outcome = @eventTitle atBat['eventStatusId']
        map = _.invert _.mapObject question['options'], (option) -> option['title']
        # This event['eventStatusId'] matches one of the options?
        outcomeOption = map[outcome]

        Promise.bind @
        .then -> @Questions.update {_id: question._id}, $set: {active: false, outcome: outcomeOption}
        .then -> @Answers.update {questionId: question._id, answered: {$ne: outcomeOption}}, {$set: {outcome: "lose"}}, {multi: true}
        .then -> @Answers.find {questionId: question._id, answered: outcomeOption}
        .map (answer) ->
          reward = Math.floor answer['wager'] * answer['multiplier']
          Promise.bind @
          .then -> @Answers.update {_id: answer._id}, {$set: {outcome: "win"}}
          .then -> @GamePlayed.update {userId: answer['userId'], gameId: game.id}, {$inc: {coins: reward}}
          .then ->
            notificationId = chance.guid()
            @Notifications.insert
              _id: notificationId
              userId: answer['userId']
              gameId: game.id
              type: "coins"
              value: reward
              read: false
              notificationId: notificationId
              dateCreated: new Date()
              message: "Nice Pickk! You got #{reward} Coins!"
              sharable: false
              shareMessage: ""
      else if not matchesBatter
        @logger.verbose "The player for event selected does not match the question batter. Increasing by 1 until event found..."
      else
        @logger.warn "Can't find a play completed for the question",

  createPitch: (old, update, diff) ->
    player = update['eventStatus']['currentBatter']
    playerId = player['playerId']
    gameId = old['_id']
    balls = update['eventStatus']['balls']
    strikes = update['eventStatus']['strikes']
    eventCount = update['old']["eventCount"]
    inning = update['eventStatus']['inning']
    atBatId = gameId + "-" + inning + "-" + eventCount + "-" + playerId
    pitchId = update['old']['lastCount'].length
    question = "#{player['firstName']} #{player['lastName']}: " + balls + " - " + strikes

    if (diff.indexOf 'inningDivision') > -1
      createDate = moment().add 2, "minutes"
    else
      createDate = new Date()

    Promise.bind @
    .then -> @getGenericMultipliersForPitch()
    # .then -> @calculateMultipliersForPitch playerId, balls, strikes
    .then (multipliers) ->
      option1 = {title: "Strike", number: 1, multiplier: multipliers['strike']}
      option2 = {title: "Ball", number: 2, multiplier: multipliers['ball']}
      option3 = {title: "Hit", number: 3, multiplier: multipliers['hit']}
      option4 = {title: "Out", number: 4, multiplier: multipliers['out']}
      option5 = undefined

      if balls is 3
        option2.title = "Walk"

      if strikes is 2
        option1.title = "Strike Out"
        option3 = {title: "Foul Ball", number: 3, multiplier: multipliers['foulball']}
        option4 = {title: "Hit", number: 4, multiplier: multipliers['hit']}
        option5 = {title: "Out", number: 5, multiplier: multipliers['out']}

      options = {option1, option2, option3, option4}
      options.option5 = option5 if option5

      Promise.bind @
      # .then -> @closeInactivePitches game, result
      .tap -> @logger.verbose "Creating the pitch Questions"
      .then -> @Questions.count {commercial: false, gameId: gameId, playerId: playerId, atBatQuestion: {$exists: false}, atBatId: atBatId, pitchId: pitchId}
      .then (found) ->
        if not found
          Promise.bind @
            .then ->
              @Questions.insert
                _id: @Questions.db.ObjectId().toString()
                dateCreated: createDate
                gameId: gameId
                playerId: playerId
                game_id: gameId
                player_id: playerId
                atBatId: atBatId
                pitchId: pitchId
                eventCount: eventCount
                inning: inning
                type: "pitch"
                period: 0
                active: true
                commercial: false
                que: question
                options: options
                usersAnswered: []
            .tap (result) ->
              questionId = result.upserted?[0]?._id
              # @logger.verbose "Create pitch question (#{question})", {gameId: gameId, playerId: playerId, atBatId: atBatId, pitchId: pitchId, questionId: _id}

  closeInactivePitches: (game, result) ->
    playNumber = result.playNumber
    pitchNumber = result.pitchNumber

    @logger.verbose "Close inactive pitches", {gameId: game.id, playNumber, pitchNumber}

    Promise.bind @
    .then -> @Questions.find {commercial: false, game_id: game.id, active: true, atBatQuestion: {$exists: false}, $or: [{play: {$ne: playNumber}}, {pitch: {$ne: pitchNumber}}]}
    .map (question) ->
      questionPlay = question['play']
      questionPitch = question['pitch']
      @logger.verbose "Close a pitch question", {questionId: question['_id'], questionPlay, questionPitch}

      play = result['plays'][questionPlay - 1]
      if not play
        @logger.warn "Can't find a play completed for the question", {questionId: question['_id'], questionPlay, questionPitch, playsAmount: result['plays'].length}
        return

      outcome = play.pitches[questionPitch - 1]

      map = _.invert _.mapObject question['options'], (option) -> option['title']
      outcomeOption = map[outcome]

      Promise.bind @
      .then -> @Questions.update {_id: question._id}, $set: {active: false, outcome: outcomeOption}
      .tap -> @logger.info "Close pitch question (#{question['que']})  with outcome (#{outcome})"
      .tap -> @logger.verbose "Close pitch question (#{question['que']})  with outcome (#{outcome})", {questionId: question['_id'], outcome: outcomeOption, play: question['play'], pitch: question['pitch']}
      .then -> @Answers.update {questionId: question._id, answered: {$ne: outcomeOption}}, {$set: {outcome: "lose"}}, {multi: true}
      .tap (result) -> @logger.verbose "There are (#{result.n}) negative answer(s) for question (#{question['que']})"
      .then -> @Answers.find {questionId: question._id, answered: outcomeOption}
      .tap (answers) -> @logger.info "There are (#{answers.length}) positive answer(s) for question (#{question['que']})"
      .map (answer) ->
        reward = Math.floor answer['wager'] * answer['multiplier']
        Promise.bind @
        .then -> @Answers.update {_id: answer._id}, {$set: {outcome: "win"}}
        .then -> @GamePlayed.update {userId: answer['userId'], gameId: game.id}, {$inc: {coins: reward}}
        .then ->
          notificationId = chance.guid()
          @Notifications.insert
            _id: notificationId
            userId: answer['userId']
            type: "score"
            read: false
            notificationId: notificationId
            dateCreated: new Date()
            message: "Nice Pickk! You got #{reward} Coins!"
            sharable: false
            shareMessage: ""
        # .tap -> @logger.verbose "Reward user (#{answer['userId']}) with coins (#{reward}) for question (#{question['que']})"

  eventTitle: (eventStatusId) ->
    results = [
      title: "Single"
      outcomes: [1, 2, 3, 4, 5, 6, 122]
    ,
      title: "Double"
      outcomes: [7, 8, 9, 10, 11, 123]
    ,
      title: "Triple"
      outcomes: [12, 13, 124]
    ,
      title: "Home Run"
      outcomes: [15, 16, 17, 18]
    ,
      title: "Out"
      outcomes: [15, 16, 17, 18]
    ]

    _.each results, (option) ->
      onList = option['outcomes'].indexOf(eventStatusId)
      if onList
        return option['title']

  calculateMultipliersForPlay: (bases, playerId) ->
    Promise.bind @
    .then -> @Players.findOne({_id: playerId})
    .then (player) ->
      stat = if player.stats.three_year['no_statistics_available_'] then player.stats.y2016extended else player.stats.three_year

      situation = switch true
        when bases.first and bases.second and bases.third then stat['bases_loaded']
        when bases.first then stat['runners_on']
        when bases.second and bases.third then stat['scoring_position']
        else stat['total']

      atBats = situation.ab
      avg = situation.avg
      hit = situation.h
      walk = parseInt(situation.bb)
      hitByBall = parseInt(situation.hbp)
      walkPercent = (walk + hitByBall ) / atBats
      homeRun = parseInt(situation.hr)
      homeRunPercent = homeRun / atBats
      triple = parseInt(situation.triple)
      triplePercent = triple / atBats
      double = parseInt(situation.double)
      doublePercent = double / atBats
      single = parseInt(hit - homeRun - double - triple)
      singlePercent = single / atBats
      outs = (atBats - hitByBall - walk - homeRun - triple - double - single)
      outPercent = outs / atBats

      outPercent = (100 - (outPercent*100).toFixed(2))
      walkPercent = (100 - (walkPercent*100).toFixed(2))
      singlePercent = (100 - (singlePercent*100).toFixed(2))
      doublePercent = (100 - (doublePercent*100).toFixed(2))
      triplePercent = (100 - (triplePercent*100).toFixed(2))
      homeRunPercent = (100 - (homeRunPercent*100).toFixed(2))

      toMultiplier = (value) =>
        switch true
          when value < 25 then @getRandomArbitrary 1.95, 2.45
          when value < 50 then @getRandomArbitrary 2.27, 3.3
          when value < 60 then @getRandomArbitrary 3.2, 4.7
          when value < 75 then @getRandomArbitrary 3.65, 4.15
          when value < 85 then @getRandomArbitrary 3.75, 5.35
          when value < 90 then @getRandomArbitrary 4.25, 6.75
          when value < 95 then @getRandomArbitrary 5.65, 8.95
          when value < 99 then @getRandomArbitrary 7.95, 14.5
          else @getRandomArbitrary 5.5, 9

      out: toMultiplier outPercent
      walk: toMultiplier walkPercent
      single: toMultiplier singlePercent
      double: toMultiplier doublePercent
      triple: toMultiplier triplePercent
      homerun: toMultiplier homeRunPercent
    .catch (error) ->
      # @logger.verbose "Fallback to generic multipliers for play. Player (#{playerId})"
      @getGenericMultipliersForPlay()

  calculateMultipliersForPitch: (playerId, balls, strikes) ->
    Promise.bind @
    .then -> @Players.findOne({_id: playerId})
    .then (player) ->

      stat = if player.stats.three_year['no_statistics_available_'] then player.stats.y2016extended else player.stats.three_year
      totalAtBat = stat.total['ab']

      currentPlayKey = "count_#{balls}_#{strikes}"
      play = stat[currentPlayKey] or player.stats.career
      playEoP = play['ab']

      # End of Play probability
      EoP = parseInt(playEoP) / parseInt(totalAtBat)
      remainingPercent = 1 - EoP
      hitPercent = play['avg'] * EoP
      outPercent = (1 - hitPercent) * EoP

      if strikes is 2
        option1EoP = play['so']
      else
        nextPlayKey = "count_#{balls}_#{strikes + 1}"
        nextPlay = stat[nextPlayKey]
        option1EoP = nextPlay?['ab'] or 1

      if balls is 3
        option2EoP = play['bb']
      else
        nextPlayKey = "count_#{balls + 1}_#{strikes}"
        nextPlay = stat[nextPlayKey]
        option2EoP = nextPlay?['ab'] or 1

      option1EoP = parseInt option1EoP
      option2EoP = parseInt option2EoP
      combinedEoP = option1EoP + option2EoP
      option1EoPPercentage = (( option1EoP / combinedEoP ) * remainingPercent).toFixed(4)
      option2EoPPercentage = (( option2EoP / combinedEoP ) * remainingPercent).toFixed(4)

      strikePercent = (100 - (option1EoPPercentage * 100).toFixed(2))
      ballPercent = (100 - (option2EoPPercentage *100).toFixed(2))
      outPercent = (100 - (outPercent*100).toFixed(2))
      hitPercent = (100 - (hitPercent*100).toFixed(2))

      toMultiplier = (value) =>
        switch true
          when value < 25 then @getRandomArbitrary 1.55,2.25
          when value < 50 then @getRandomArbitrary 1.75, 2.25
          when value < 60 then @getRandomArbitrary 2.5,2.75
          when value < 75 then @getRandomArbitrary 2.75, 3.25
          when value < 85 then @getRandomArbitrary 3.25, 2.75
          when value < 90 then @getRandomArbitrary 3.75, 4.5
          else @getRandomArbitrary 3.5, 4.5

      strike: toMultiplier strikePercent
      ball: toMultiplier ballPercent
      out: toMultiplier outPercent
      hit: toMultiplier hitPercent
      foulball: @getRandomArbitrary(1.5, 2)
    .catch (error) ->
      # @logger.verbose "Fallback to generic multipliers for pitch. Player (#{playerId})"
      @getGenericMultipliersForPitch()

  getGenericMultipliersForPlay: ->
    out: @getRandomArbitrary 1.95, 2.95
    walk: @getRandomArbitrary 3.05, 5.65
    single: @getRandomArbitrary 3.35, 5.65
    double: @getRandomArbitrary 6.05, 8.65
    triple: @getRandomArbitrary 9.05, 15.65
    homerun: @getRandomArbitrary 8.05, 12.65

  getGenericMultipliersForPitch: ->
    strike: @getRandomArbitrary 1.55, 2.5
    ball: @getRandomArbitrary 1.45, 2.65
    out: @getRandomArbitrary 2.05, 3.65
    hit: @getRandomArbitrary 3.05, 5.65
    foulball: @getRandomArbitrary 1.65, 2.45

  getRandomArbitrary: (min, max) -> parseFloat((Math.random() * (max - min) + min).toFixed(2))
