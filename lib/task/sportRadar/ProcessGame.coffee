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
      .then -> @checkGameStatus old, update
      .then -> @handleGame old, update
      .return true
      .catch (error) =>
        @logger.error error.message, _.extend({stack: error.stack}, error.details)
        retry(error)

  handleGame: (old, update) ->
    result = @gameParser.getPlay update

    if result
      Promise.bind @
      .then -> @enrichGame old, result
      .then -> @detectChange old, result

  enrichGame: (old, update) ->
    if !old['old']
      @SportRadarGames.update {_id: update.eventId}, {$set: update}
    else if !update['old'] || !old['old']
      console.log "[Global] No old or update????????"
      return
    else if update['eventStatus']['eventStatusId'] isnt 2
      console.log "Something is wrong. Shutting this whole thing down..."
      return

  detectChange: (old, result) ->
    oldStuff = old['eventStatus']
    newStuff = result['eventStatus']

    oldInning = if old['old'] then old['old']['inningDivision'] else "Top"
    newInning = result['old']['inningDivision']

    oldPlayer = if old['old'] then old["old"]['eventStatus']['currentBatter']['playerId']  else 0
    newPlayer = result['eventStatus']['currentBatter']
    list = ["strikes", "balls", "outs", "currentBatter", "eventStatusId", "innings", "inningDivision", "runnersOnBase"]

    ignoreList =  [35, 42, 89, 96, 97, 98]
    onIgnoreList = ignoreList.indexOf result['old']['eventId']

    @oldPitch = if old['old'] then old["old"]['lastCount'].length else 0
    @newPitch = result["old"]['lastCount'].length
    pitchDiff = @newPitch - @oldPitch

    diff = []
    _.map list, (key) ->
      compare = _.isEqual oldStuff[key], newStuff[key]
      if not compare
        diff.push key

    Promise.bind @
      .then -> @SportRadarGames.find {eventId: old['eventId'] }
      .then (result) -> @checkCommericalStatus result[0], old, result, newPlayer

    if oldInning isnt newInning
      console.log "---------------------------"
      console.log "New inning!!!!!!"
      console.log "---------------------------\n"
      atBatId = old['_id'] + "-" + result['eventStatus']['inning'] + "-" + result['old']["eventCount"] + "-" + oldPlayer
      promiseRetry {retries: 1000, factor: 1}, (retry) =>
        Promise.bind @
          .then -> @handleCommercialBreak old, result
          .then -> @resolveCommercialQuestions old, true
          .then -> @closeInactiveAtBats old, result, atBatId
          .then -> @closeInactivePitches old, result, atBatId, 0

    else if oldPlayer isnt newPlayer['playerId']
      console.log "---------------------------"
      console.log "New Player!!!!!"
      console.log "---------------------------\n"
      inningDivision = result['eventStatus']['inningDivision']
      promiseRetry {retries: 1000, factor: 1}, (retry) =>
        Promise.bind @
          .then -> @createPitch old, result, newPlayer, 0
          .tap -> @logger.verbose "Created 0-0"
          .then -> @createAtBat old, result, newPlayer
          .tap -> @logger.verbose "Created New At Bat"

    else if (diff.length > 0 || pitchDiff > 0) && onIgnoreList is -1
      if (diff.indexOf "balls") > -1 || (diff.indexOf "strikes") > -1
        # @logger.verbose "Diff Change!"
        pitchNumber = (result['old']['lastCount'].length)
        player = result['old']['player']
        promiseRetry {retries: 1000, factor: 1}, (retry) =>
          Promise.bind @
            .then -> @createPitch old, result, player, pitchNumber

      else if pitchDiff isnt 0
        # @logger.verbose "pitchDiff Change!"
        pitchNumber = (result['old']['lastCount'].length)
        player = result['old']['player']
        promiseRetry {retries: 1000, factor: 1}, (retry) =>
          Promise.bind @
            .then -> @createPitch old, result, player, pitchNumber

  checkGameStatus: (old, update) ->
    if update['eventStatus']['eventStatusId'] is 4
      #This should be a method!
      update['status'] = "completed"
      update['close_processed'] = true
      update['live'] = false
      @SportRadarGames.update {_id: old['_id']}, {$set: update}
      return
    # elseif update

  checkCommericalStatus: (game, old, update, newPlayer) ->
    if not game.commercialStartedAt
      return
    now = moment()
    timeout = now.diff(game.commercialStartedAt, 'minute')
    commercialTime = @dependencies.settings['common']['commercialTime']
    if timeout >= commercialTime
      Promise.bind @
        .then -> @SportRadarGames.update {_id: game._id}, {$set: {commercial: false}, $unset: {commercialStartedAt: 1}}
        .then -> @closeActiveCommercialQuestions game
        .tap -> @logger.verbose "Creating first player questions."
        .then -> @createPitch old, update[0], newPlayer, 0
        .tap -> @logger.verbose "Created 0-0"
        .then -> @createAtBat old, update[0], newPlayer
        .tap -> @logger.verbose "Created New At Bat After Commercial"

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
    if not game.commercial
      Promise.bind @
      .then -> @SportRadarGames.update {_id: game._id}, {$set: {commercial: true, commercialStartedAt: new Date()}}
      .tap -> @logger.verbose "Commercial flag has been set for game (#{game.name})"
      .then -> @createCommercialQuestions game, result

  createCommercialQuestions: (game, result) ->
    templates = [
      title: "Hit a Single"
      outcomes: [1, 2, 3, 4, 5, 6, 122]
    ,
      title: "Hit a Double"
      outcomes: [7, 8, 9, 10, 11, 123]
    ,
      title: "Hit a Triple"
      outcomes: [12, 13, 124]
    ,
      title: "Hit a Home Run"
      outcomes: [15, 16, 17, 18]
    ,
      title: "Steal a Base"
      outcomes: [15, 16, 17, 18]
    ,
      title: "Get Hit by a Pitch"
      outcomes: ["61"]
    ]
    inning =  result['eventStatus']['inning']
    inningDivision = result['eventStatus']['inningDivision']
    if inningDivision is "Top"
      team = result['teams'][1]
    else if inningDivision is "Bottom"
      team = result['teams'][0]

    Promise.bind @
    .return team
    .then (team) ->
      name = team.nickname
      templates = _.sample templates, 2
      Promise.all (for template in templates
        do (template) =>
          text = "Will #{name} #{template.title} in the #{inning} inning?"

          options =
            option1: {title: "True", number: 1, multiplier: 4}
            option2: {title: "False",  number: 2, multiplier: 4}

          Promise.bind @
          .then ->
            @Questions.insert
              _id: @Questions.db.ObjectId().toString()
              que: text
              type: "freePickk"
              game_id: game._id
              gameId: game._id
              teamId: team.teamId
              inningDivision: inningDivision
              inning: inning
              period: 0
              dateCreated: new Date()
              active: true
              processed: false
              commercial: true
              binaryChoice: true
              options: options
              outcomes: template.outcomes
              usersAnswered: []
          .tap ->
            @logger.verbose "Create commercial question '#{text}' for the game (#{game.name})"
      )

  closeActiveCommercialQuestions: (game) ->
    Promise.bind @
    .then -> @Questions.find {commercial: true, game_id: game._id, active: true}
    .map (question) ->
      Promise.bind @
      .then -> @Questions.update {_id: question._id}, {$set: {active: null, lastUpdated: new Date()}}
      .tap ->
        @logger.info "Close commercial question '#{question['que']}' for the game (#{game.name})"

  resolveCommercialQuestions: (game, completed, event) ->
    Promise.bind @
      .then -> @Questions.find {gameId: game['_id'], commercial: true, processed: false, active: null, inning: game['old']['inning'], inningDivision: game['old']['inningDivision']}
      .map (result) ->
        if completed is true
          @rewardForCommercialQuestion game, result, false
        else
          list = result['outcomes']
          onList = list.indexOf event['pbpDetailId']
          if (onList) > -1
            @rewardForCommercialQuestion game, result, true

  rewardForCommercialQuestion: (game, question, correct) ->
    if correct
      outcome = "option1"
    else if !correct
      outcome = "option2"

    Promise.bind @
      .then -> @Questions.update {_id: question._id}, {$set: {active: false, outcome: outcome, processed: true, lastUpdated: new Date()}}
      .then -> @Answers.update {questionId: question._id, answered: {$ne: outcome}}, {$set: {outcome: "lose"}}, {multi: true}
      .then -> @Answers.find {questionId: question._id, answered: outcome}
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
        .tap -> @logger.verbose "Reward user (#{answer['userId']}) with coins (#{reward}) for question (#{question['que']})"
        .tap -> @logger.verbose "Outcome of the question... ", question

  createAtBat: (old, update, player) ->
    playerId = if player then player['playerId']
    console.log update['old']
    atBatId = old['_id'] + "-" + update['old']['inning'] + "-" + update['old']["eventCount"] + "-" + playerId
    question = "End of #{player['firstName']} #{player['lastName']}'s at bat."

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
      .then -> @closeInactiveAtBats old, update, atBatId
      .then -> @Questions.count {commercial: false, game_id: old["_id"], player_id: playerId, atBatQuestion: true, atBatId: atBatId}
      .then (found) ->
        if not found
          Promise.bind @
          .then ->
            @Questions.insert
              _id: @Questions.db.ObjectId().toString()
              dateCreated: new Date()
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
              background: "background: linear-gradient(rgba(34, 44, 49, .0), rgba(34, 44, 49, .5)), url('https://image.shutterstock.com/z/stock-photo-queens-ny-april-the-game-between-the-new-york-mets-and-florida-marlins-about-to-begin-at-57937108.jpg'); height: 75px; background-position-x: 46%; background-position-y: 0%; "
              commercial: false
              que: question
              options: options
              usersAnswered: []
          .tap (result) ->
            questionId = result.upserted?[0]?._id
            @logger.verbose "Create atBat question (#{question})"

  closeInactiveAtBats: (old, update, atBatId) ->
    ignoreList =  [35, 42, 89, 96, 97, 98]
    onIgnoreList = ignoreList.indexOf update['old']['eventId']
    if onIgnoreList > -1
      @logger.verbose "Not really closed...", update['old']['eventId']
      return

    gameId = old['_id']
    Promise.bind @
    .then -> @Questions.find {commercial: false, gameId: gameId, active: true, atBatQuestion: true, atBatId: {$ne: atBatId}}
    .map (question) ->
      @Questions.update {_id: question['_id']}, $set: {active: false, lastUpdated: new Date()}
      questionEventCount = question['eventCount']
      eventCount = update['old']['eventCount']
      compareEventCount = eventCount - questionEventCount
      event = @gameParser.findSpecificEvent update, questionEventCount - 1
      outcome = @eventTitle event['pbpDetailId']

      map = _.invert _.mapObject question['options'], (option) -> option['title']
      outcomeOption = map[outcome] #could fail here

      Promise.bind @
      .then -> @resolveCommercialQuestions update, false, event
      .then -> @Questions.update {_id: question._id}, $set: {active: false, outcome: outcomeOption, lastUpdated: new Date()}
      .then -> @Answers.update {questionId: question._id, answered: {$ne: outcomeOption}}, {$set: {outcome: "lose"}}, {multi: true}
      .then -> @Answers.find {questionId: question._id, answered: outcomeOption}
      .map (answer) ->
        reward = Math.floor answer['wager'] * answer['multiplier']
        Promise.bind @
        .then -> @Answers.update {_id: answer._id}, {$set: {outcome: "win"}}
        .then -> @GamePlayed.update {userId: answer['userId'], gameId: gameId}, {$inc: {coins: reward}}
        .tap -> @logger.verbose "Awarding correct users!"
        .then ->
          notificationId = chance.guid()
          @Notifications.insert
            _id: notificationId
            userId: answer['userId']
            gameId: gameId
            type: "coins"
            value: reward
            read: false
            notificationId: notificationId
            dateCreated: new Date()
            message: "Nice Pickk! You got #{reward} Coins!"
            sharable: false
            shareMessage: ""

  createPitch: (old, update, player, pitchNumber) ->
    if !update['old'] || !old['old']
      console.log "No old or update????????"
      update = update[0]
      console.log update['old']

    playerId = player['playerId']
    gameId = old['_id']
    eventCount = update['old']["eventCount"]
    if !update['old']['inning']
      console.log update['old']
    inning = update['old']['inning']
    atBatId = gameId + "-" + inning + "-" + eventCount + "-" + playerId
    last = _.last update['old']['lastCount'], 1
    result =  if last[0] then last[0].result
    balls = if last[0] then last[0].balls else 0
    strikes = if last[0] then last[0].strikes else 0
    foulArray = ['F', 'G', 'R', 'V']
    strikesArray = ['S', 'T', 'J', 'U', 'O']
    ballArray = ['B', 'L', 'M', '#', 'P']
    hitArray = ['I', 'H']

    if pitchNumber is 0
      balls = 0
      strikes = 0

      # if strikes > 0
    if strikes < 2 && (strikesArray.indexOf result) > -1
      strikes += 1
    else if strikes is 2 && (strikesArray.indexOf result) > -1
      @closeInactivePitches old, update, atBatId, pitchNumber
      event = @gameParser.findSpecificEvent update, eventCount - 1
      @logger.verbose event
      @logger.verbose "Strikeout!"
      # return
    else if strikes < 2 && (foulArray.indexOf result) > -1
      strikes += 1

      # if balls > 0
    if balls < 3 && (ballArray.indexOf result) > -1
      balls += 1
    else if balls is 3 && (ballArray.indexOf result) > -1
      @closeInactivePitches old, update, atBatId, pitchNumber
      event = @gameParser.findSpecificEvent update, eventCount - 1
      @logger.verbose event
      @logger.verbose "Walk!"
      # return

    if (hitArray.indexOf result) > -1
      @closeInactivePitches old, update, atBatId, pitchNumber
      event = @gameParser.findSpecificEvent update, eventCount - 1
      @logger.verbose event
      @logger.verbose "Hit!"
      # return

    pitchNumber = pitchNumber + 1

    question = "#{player['firstName']} #{player['lastName']}: " + balls + " - " + strikes + " (##{pitchNumber})"
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
      # @logger.verbose question

      Promise.bind @
      .then -> @closeInactivePitches old, update, atBatId, pitchNumber
      .then -> @Questions.count {commercial: false, gameId: gameId, playerId: playerId, atBatQuestion: {$exists: false}, atBatId: atBatId, pitchNumber: pitchNumber}
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
                pitchNumber: pitchNumber
                eventCount: eventCount
                inning: inning
                type: "pitch"
                period: 0
                active: true
                commercial: false
                que: question
                background: "background: linear-gradient(rgba(34, 44, 49, .0), rgba(34, 44, 49, .5)), url('/baseball-background.png'); height: 75px; background-position-x: 46%; background-position-y: 100%; "
                options: options
                usersAnswered: []
            .tap (result) ->
              questionId = result.upserted?[0]?._id
              # @logger.verbose "Create pitch question (#{question})", {gameId: gameId, playerId: playerId, atBatId: atBatId, pitchNumber: pitchNumber}

  closeInactivePitches: (old, update, atBatId, pitchNumber) ->
    gameId = old['_id']
    Promise.bind @
    .then -> @Questions.find {commercial: false, gameId: old['_id'], active: true, atBatQuestion: {$exists: false}, $or: [{atBatId: {$ne: atBatId}}, {pitchNumber: {$ne: pitchNumber}}]}
    .map (question) ->
      # @logger.verbose "Closing #{question['que']} with current count: #{pitchNumber}"
      @Questions.update {_id: question['_id']}, $set: {active: false, lastUpdated: new Date()}

      questionEventCount = question['eventCount']
      eventCount = update['old']['eventCount']
      compareEventCount = questionEventCount - eventCount

      questionPitchCount = question['pitchNumber']
      pitchCount = update['old']['lastCount']
      comparePitchCount = questionPitchCount - pitchCount
      if pitchCount.length is 0
        event = @gameParser.findSpecificEvent update, questionEventCount - 1
        pitchCount = event['pitchDetails']

      pitch = _.last pitchCount
      if !pitch
        console.log "No Pitch"
        console.log update['old']
        console.log pitchCount
        console.log question
      pitchOutcome = @pitchTitle pitch['result']

      strikes = pitch.strikes
      balls = pitch.balls
      result = pitch.result
      foulArray = ['F', 'G', 'R', 'V']
      strikesArray = ['S', 'T', 'J', 'U', 'O']
      ballArray = ['B', 'L', 'M', '#', 'P']
      hitArray = ['I', 'H']

      if strikes < 2 && (foulArray.indexOf result) > -1
        pitchOutcome = "Foul Ball"

      if strikes is 2 && (strikesArray.indexOf result) > -1
        pitchOutcome = "Strike Out"

      if balls is 3 && (ballArray.indexOf result) > -1
        pitchOutcome = "Walk"

      if (hitArray.indexOf result) > -1
        eventId = update['old']['eventId']
        pitchOutcome = @eventTitle eventId
        if pitchOutcome isnt "Out"
          pitchOutcome = "Hit"

      map = _.invert _.mapObject question['options'], (option) -> option['title']
      outcomeTitle = pitchOutcome
      outcomeOption = map[outcomeTitle]

      Promise.bind @
      .then -> @Questions.update {_id: question._id}, $set: {active: false, outcome: outcomeOption, lastUpdated: new Date()}
      .then -> @Answers.update {questionId: question._id, answered: {$ne: outcomeOption}}, {$set: {outcome: "lose"}}, {multi: true}
      .then -> @Answers.find {questionId: question._id, answered: outcomeOption}
      .map (answer) ->
        reward = Math.floor answer['wager'] * answer['multiplier']
        Promise.bind @
        .then -> @Answers.update {_id: answer._id}, {$set: {outcome: "win"}}
        .then -> @GamePlayed.update {userId: answer['userId'], gameId: gameId}, {$inc: {coins: reward}}
        .tap -> @logger.verbose "Awarding correct users!"
        .then ->
          notificationId = chance.guid()
          @Notifications.insert
            _id: notificationId
            question: question._id
            userId: answer['userId']
            gameId: gameId
            type: "coins"
            value: reward
            read: false
            notificationId: notificationId
            dateCreated: new Date()
            message: "Nice Pickk! You got #{reward} Coins!"
            sharable: false
            shareMessage: ""

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
      outcomes: [15, 16, 17, 18, 26, 27, 28, 30, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 56, 57, 59, 65, 67, 68, 69, 70, 71, 72, 73, 77, 78, 82, 85, 91, 92, 93, 94, 126, 127, 136]
    ,
      title: "Walk"
      outcomes: [61, 106]
    ]
    # Loop over each object in array
    result = ""
    for item in results
      if (item['outcomes'].indexOf eventStatusId) > -1
        result = item['title']
    return result

  pitchTitle: (pitchTitle) ->
    results = [
      title: "Strike"
      outcomes: ['S', 'T', 'J', 'U', 'O']
    ,
      title: "Ball"
      outcomes: ['B', 'L', 'M', '#', 'P']
    ,
      title: "Hit"
      outcomes: ['I', 'H']
    ,
      title: "Foul Ball"
      outcomes: ['F', 'G', 'R', 'V']
    ]

    result = ""
    for item in results
      if (item['outcomes'].indexOf pitchTitle) > -1
        result = item['title']
    return result

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
