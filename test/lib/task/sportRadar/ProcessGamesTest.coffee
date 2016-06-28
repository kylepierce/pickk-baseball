createDependencies = require "../../../../helper/dependencies"
settings = (require "../../../../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")
Promise = require "bluebird"
moment = require "moment"
ImportGames = require "../../../../lib/task/sportRadar/ImportGames"
loadFixtures = require "../../../../helper/loadFixtures"
ProcessGames = require "../../../../lib/task/sportRadar/ProcessGames"
SportRadarGame = require "../../../../lib/model/sportRadar/SportRadarGame"
TwoActiveGamesFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/TwoActiveGames.json"
QuestionsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/Questions.json"
ActualQuestionsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/ActualQuestions.json"
NonActualQuestionsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/NonActualQuestions.json"
ActiveFullGameFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/ActiveFullGame.json"
ActiveGameNoInningsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/ActiveGameNoInnings.json"
ActiveGameNoHalfsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/ActiveGameNoHalfs.json"
ActiveGameNoPlaysFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/ActiveGameNoPlays.json"
ActiveGameNoPitchesFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/processGames/collection/ActiveGameNoPitches.json"

describe "Process imported games and question management", ->
  dependencies = createDependencies settings, "PickkImport"
  mongodb = dependencies.mongodb

  processGames = undefined
  
  SportRadarGames = mongodb.collection("SportRadarGames")
  Questions = mongodb.collection("questions")

  activeGameId = "fec58a7a-eff7-4eec-9535-f64c42cc4870"
  inactiveGameId = "2b0ba18a-41f5-46d7-beb3-1e86b9a4acc0"
  actualActiveQuestionId = "active_question_for_active_game"
  nonActualActiveQuestionId = "active_question_for_inactive_game"

  beforeEach ->
    processGames = new ProcessGames dependencies

    Promise.bind @
    .then ->
      Promise.all [
        SportRadarGames.remove()
        Questions.remove()
      ]

  it 'should fetch only active games', ->
    Promise.bind @
    .then -> loadFixtures TwoActiveGamesFixtures, mongodb 
    .then -> processGames.getActiveGames()
    .then (games) -> 
      should.exist games
      games.should.be.an "array"
      games.length.should.be.equal 2

  it 'should disable active questions for inactive games', ->
    Promise.bind @
    .then -> loadFixtures TwoActiveGamesFixtures, mongodb
    .then -> loadFixtures QuestionsFixtures, mongodb
    .then -> Questions.findOne({id: actualActiveQuestionId})
    .then (question) ->
      # this question shouldn't be disabled
      should.exist question
      question.should.be.an "object"
      {active} = question
      should.exist active
      active.should.be.equal true
    .then -> Questions.findOne({id: nonActualActiveQuestionId})
    .then (question) ->
      # but this should be
      should.exist question
      question.should.be.an "object"
      {active} = question
      should.exist active
      active.should.be.equal true
    .then -> processGames.getActiveGames()
    .then (games) -> processGames.closeQuestionsForInactiveGames(games)
    .then -> Questions.findOne({id: actualActiveQuestionId})
    .then (question) ->
      # it's still active
      should.exist question
      question.should.be.an "object"
      {active} = question
      should.exist active
      active.should.be.equal true
    .then -> Questions.findOne({id: nonActualActiveQuestionId})
    .then (question) ->
      # and this one have had to be disabled
      should.exist question
      question.should.be.an "object"
      {active} = question
      should.exist active
      active.should.be.equal false

  it 'should select the last inning', ->
    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) ->
      should.exist game
      game.should.be.an "object"
      processGames.getLastInning game
    .then (inning) ->
      should.exist inning
      inning.should.be.an "object"

      {number} = inning
      should.exist number
      number.should.equal 4

  it 'should work correctly when there is no innings', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameNoInningsFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) ->
      should.exist game
      game.should.be.an "object"
      processGames.getLastInning game
    .then (inning) ->
      should.not.exist inning

  it 'should select the last half', ->
    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGames.getLastInning game
    .then (inning) -> processGames.getLastHalf inning
    .then (half) ->
      should.exist half
      half.should.be.an "object"

      {fixture_right_half} = half
      should.exist fixture_right_half

  it 'should work correctly when there is no halfs', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameNoHalfsFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGames.getLastInning game
    .then (inning) -> processGames.getLastHalf inning
    .then (half) ->
      should.not.exist half

  it 'should select the last play', ->
    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGames.getLastInning game
    .then (inning) -> processGames.getLastHalf inning
    .then (half) -> processGames.getLastPlay half
    .then (play) ->
      should.exist play
      play.should.be.an "object"

      {id} = play
      should.exist id
      id.should.be.equal "72cac512-f8c3-4465-97fd-c2212092679c"

  it 'should work correctly when there is no plays', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameNoPlaysFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGames.getLastInning game
    .then (inning) -> processGames.getLastHalf inning
    .then (half) -> processGames.getLastPlay half
    .then (play) ->
      should.not.exist play

  it 'should select the last pitch', ->
    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGames.getLastInning game
    .then (inning) -> processGames.getLastHalf inning
    .then (half) -> processGames.getLastPlay half
    .then (play) -> processGames.getLastPitch play
    .then (pitch) ->
      should.exist pitch
      pitch.should.be.an "object"

      {id} = pitch
      should.exist id
      id.should.be.equal "33c5d1c5-a077-4383-af67-f9fb603dae5e"

  it 'should work correctly when there is no pitches', ->
    Promise.bind @
    .then -> loadFixtures ActiveGameNoPitchesFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGames.getLastInning game
    .then (inning) -> processGames.getLastHalf inning
    .then (half) -> processGames.getLastPlay half
    .then (play) -> processGames.getLastPitch play
    .then (pitch) ->
      should.not.exist pitch

  it 'should create new play question', ->
    game = undefined
    players = undefined
    play = undefined

    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .tap (game) -> players = processGames.getPlayers game
    .then (_game) -> game = _game; processGames.getLastInning game
    .then (inning) -> processGames.getLastHalf inning
    .then (half) -> processGames.getLastPlay half
    .then (_play) -> play = _play; processGames.handlePlay game, players, play
    .then -> Questions.findOne({game_id: activeGameId, play_id: "72cac512-f8c3-4465-97fd-c2212092679c", atBatQuestion: true})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active} = question
      should.exist active
      active.should.be.equal true

  it 'should update actual play question', ->
    game = undefined
    players = undefined
    play = undefined

    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> loadFixtures ActualQuestionsFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .tap (game) -> players = processGames.getPlayers game
    .then (_game) -> game = _game; processGames.getLastInning game
    .then (inning) -> processGames.getLastHalf inning
    .then (half) -> processGames.getLastPlay half
    .then (_play) -> play = _play; processGames.handlePlay game, players, play
    .then -> Questions.findOne({id: "active_question_for_active_game"})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active, options} = question
      should.exist active
      # should be still active
      active.should.be.equal true

      # check options have been updated
      should.exist options

  it 'should disable non-actual play question', ->
    game = undefined
    players = undefined
    play = undefined

    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> loadFixtures NonActualQuestionsFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .tap (game) -> players = processGames.getPlayers game
    .then (_game) -> game = _game; processGames.getLastInning game
    .then (inning) -> processGames.getLastHalf inning
    .then (half) -> processGames.getLastPlay half
    .then (_play) -> play = _play; processGames.handlePlay game, players, play
    .then -> Questions.findOne({id: "non_actual_question_for_active_game"})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active} = question
      should.exist active
      active.should.be.equal false

  it 'should create new pitch question', ->
    game = undefined
    players = undefined
    play = undefined
    pitch = undefined

    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .tap (game) -> players = processGames.getPlayers game
    .then (_game) -> game = _game; processGames.getLastInning game
    .then (inning) -> processGames.getLastHalf inning
    .then (half) -> processGames.getLastPlay half
    .then (_play) -> play = _play; processGames.getLastPitch play
    .then (_pitch) -> pitch = _pitch; processGames.handlePitch game, players, play, pitch
    .then -> Questions.findOne({game_id: activeGameId, pitch_id: "33c5d1c5-a077-4383-af67-f9fb603dae5e", atBatQuestion: {$exists: false}})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active} = question
      should.exist active
      active.should.be.equal true

  it 'should update actual pitch question', ->
    game = undefined
    players = undefined
    play = undefined
    pitch = undefined

    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> loadFixtures ActualQuestionsFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .tap (game) -> players = processGames.getPlayers game
    .then (_game) -> game = _game; processGames.getLastInning game
    .then (inning) -> processGames.getLastHalf inning
    .then (half) -> processGames.getLastPlay half
    .then (_play) -> play = _play; processGames.getLastPitch play
    .then (_pitch) -> pitch = _pitch; processGames.handlePitch game, players, play, pitch
    .then -> Questions.findOne({id: "active_pitch_question_for_active_game"})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active, options} = question
      should.exist active
      # should be still active
      active.should.be.equal true

      # check options have been updated
      should.exist options

  it 'should disable non-actual play question', ->
    game = undefined
    players = undefined
    play = undefined
    pitch = undefined

    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> loadFixtures NonActualQuestionsFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .tap (game) -> players = processGames.getPlayers game
    .then (_game) -> game = _game; processGames.getLastInning game
    .then (inning) -> processGames.getLastHalf inning
    .then (half) -> processGames.getLastPlay half
    .then (_play) -> play = _play; processGames.getLastPitch play
    .then (_pitch) -> pitch = _pitch; processGames.handlePitch game, players, play, pitch
    .then -> Questions.findOne({id: "non_actual_pitch_question_for_active_game"})
    .then (question) ->
      should.exist question
      question.should.be.an "object"

      {active} = question
      should.exist active
      # should be still active
      active.should.be.equal false

  it 'should parse information about players', ->
    Promise.bind @
    .then -> loadFixtures ActiveFullGameFixtures, mongodb
    .then -> SportRadarGames.findOne({id: activeGameId})
    .then (game) -> processGames.getPlayers game
    .then (players) ->
      should.exist players
      players.should.be.an "object"

      player = players['abbda8e1-2274-4bf0-931c-691cf8bf24c6']
      should.exist player
      should.exist player.first_name
      player.first_name.should.be.equal 'Avisail'
      should.exist player.last_name
      player.last_name.should.be.equal 'Garcia'
