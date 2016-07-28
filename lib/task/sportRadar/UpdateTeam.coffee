_ = require "underscore"
cheerio = require('cheerio')
moment = require "moment"
request = require "request-promise"
promiseRetry = require 'promise-retry'
Match = require "mtr-match"
Promise = require "bluebird"
Task = require "../Task"
Team = require "../../model/Team"
Player = require "../../model/Player"

module.exports = class extends Task
  constructor: (dependencies) ->
    super

    Match.check dependencies, Match.ObjectIncluding
      sportRadar: Match.Any
      mongodb: Match.Any

    @Teams = dependencies.mongodb.collection("teams")
    @Players = dependencies.mongodb.collection("players")
    @logger = @dependencies.logger

  execute: (teamId) ->
    Promise.bind @
    .tap -> @logger.verbose "Start UpdateTeam with teamId (#{teamId})"
    .then -> @Teams.findOne({_id: teamId})
    .then (team) ->
      if team
        teamName = team['fullName']

        shouldUpdate = not team.updatedAt or moment().diff(team.updatedAt, 'days') > 0
        if shouldUpdate
          @logger.info "Update team #{teamName}"
          @updateTeam team
        else
          @logger.verbose "Team #{teamName} has been updated recently. Don't update it now."
      else
        @logger.info "Create team with ID #{teamId}"
        @createTeam teamId
    .tap -> @logger.verbose "End UpdateTeam with teamId (#{teamId})"

  updateTeam: (team) ->
    teamId = team['_id']

    @fetchTeam teamId
    .then (team) ->
      object = new Team team

      Promise.bind @
      .then -> @Teams.update object.getSelector(), {$set: object}
      .tap -> @logger.verbose "Team #{object['fullName']} has been successfully updated."
      .return team.players
      .map @handlePlayer

  createTeam: (teamId) ->
    @fetchTeam teamId
    .then (team) ->
      now = new Date()
      object = new Team team
      object.createdAt = now

      Promise.bind @
      .then -> @Teams.insert object
      .tap -> @logger.verbose "Team #{object['fullName']} has been successfully created."
      .return team.players
      .tap (players) -> _.each players, (player) -> player['team_id'] = teamId # enrich original data
      .map @handlePlayer

  fetchTeam: (teamId) ->
    Promise.bind @
    .tap -> @logger.verbose "Get getTeamProfile for team (#{teamId})"
    .then -> @dependencies.sportRadar.getTeamProfile teamId
    .tap (response) -> @logger.verbose "Got response for getTeamProfile. Players number (#{response.players.length})"

  handlePlayer: (playerData) ->
    playerId = playerData['id']
    playerName = playerData['full_name']

    Promise.bind @
    .tap -> @logger.verbose "Handle player (#{playerName})[#{playerId}]"
    .then -> @Players.findOne({_id: playerId})
    .then (player) ->
      if player
        shouldUpdate = not player.updatedAt or moment().diff(player.updatedAt, 'days') > 0
        if shouldUpdate
          @logger.info "Update player #{playerName}"
          @updatePlayer playerData
        else
          @logger.verbose "Player #{playerName} has been updated recently. Don't update it now."
      else
        @logger.info "Create player (#{playerName})[#{playerId}]"
        @createPlayer playerData

  updatePlayer: (data) ->
    object = new Player data

    Promise.bind @
    .then -> @fetchPlayerStats object
    .then (extension) ->
      _.extend object, extension

      Promise.bind @
      .then -> @Players.update object.getSelector(), {$set: object}
      .tap -> @logger.verbose "Player #{object['name']} has been successfully updated."

  createPlayer: (data) ->
    now = new Date()
    object = new Player data
    object.createdAt = now

    Promise.bind @
    .then -> @fetchPlayerStats object
    .then (extension) ->
      _.extend object, extension

      Promise.bind @
      .then -> @Players.insert object
      .tap -> @logger.verbose "Player #{object['name']} has been successfully created."

  fetchPlayerStats: (player) ->
    query = player.name

    promiseRetry (retry, number) =>
      Promise.bind @
        .tap -> @logger.verbose "Fetch statistics about player (#{query})"
        .then ->
          options =
            uri: "http://espn.go.com/mlb/players"
            json: true
            qs:
              search: query

          request options
        .tap -> @logger.verbose "Statistics about player (#{query}) has been successfully fetched"
        .then @parsePlayerStats
        .catch (error) ->
          @logger.warn "Can't fetch data about player (#{query}). Try to fetch by last name (#{player.lastName})", error
          if query isnt player.lastName
            query = player.lastName
            retry(error)
          else
            @logger.error "Can't fetch data about player (#{player.name}).", error

  parsePlayerStats: (data) ->
    matches = data.match /var playerId = (\d+);/
    mlbId = matches[1]

    $ = cheerio.load data
    info = $('.general-info ', '.mod-content').first()
    general = info.text()
    number = general.slice(0,3)
    bats = general.indexOf('Bats:')
    throws = general.indexOf('Throws:')
    batOrThrow = Math.min(throws, bats)

    bats = general.slice((bats + 6), (bats + 7))
    throws = general.slice((throws+8), (throws+9))
    position = general.slice(4,batOrThrow)

    playerInfo = {number, bats, throws, position, mlbId}

    general = $('.tablehead', '.mod-container')
    text = general.text()
    year2016 = text.indexOf('2016')
    seasons = text.indexOf('Season Averages')
    text = text.slice((year2016+4), (seasons))

    playerInfo.stats = {}
    playerInfo.stats.y2016 = {}
    playerInfo.stats.career = {}

    year2016 = text.indexOf('2016') # Find 2016 in the stats
    totals = text.indexOf('Total') # Find career total in the stats
    seasons = text.indexOf('Season Averages') # Where to end after career stats
    firstDigit = text.search(/\d/) # Index of first digit
    text2016 = text.slice((firstDigit), (totals)) # 2016 Stats
    seasons = text.slice((totals+6), (seasons)) # Career Stats
    text2016 = text2016.split('\n'); # Remove the line break
    seasons = seasons.split('\n'); # Remove the line break
    statsArray = ["ab", "r", "h", "double", "triple", "hr", "rbi", "bb", "so", "sb", "cs", "avg", "obp", "slg", "ops", "war"]

    for i in [0..16]
      statName = statsArray[i]
      stat = seasons[i+1]
      if (stat == "--" || stat == undefined || stat == null)
        stat = 0
      else
        stat = parseFloat(seasons[i+1])
      playerInfo.stats.career[statName] = stat

    for i in [0..16]
      statName = statsArray[i]
      stat = text2016[i+1]
      if(stat == "--" || stat == undefined || stat == null)
        stat = 0
      else
        stat = parseFloat(text2016[i+1])
      playerInfo.stats.y2016[statName] = stat

    Promise.bind @
    .then -> @getExtendedPlayerInfo playerInfo
    .then -> @getExtend2016Info playerInfo
    .then -> playerInfo

  getExtendedPlayerInfo: (playerInfo) ->
    id = playerInfo['mlbId']

    options =
      uri: "http://espn.go.com/mlb/player/splits/_/id/#{id}/type/batting3/"
      json: true

    promiseRetry (retry, number) =>
      Promise.bind @
      .tap -> @logger.verbose "Fetch additional info about player (#{id})"
      .then -> request options
      .tap -> @logger.verbose "Additional info about player (#{id}) has been successfully fetched"
      .then @parsePlayerExtendedInfo
      .then (stats) -> _.extend playerInfo.stats, {three_year: stats}
      .catch (error) ->
        @logger.error "Can't fetch data about player (#{id}). Attempt: #{number}", error
        retry(error)

  getExtend2016Info: (playerInfo) ->
    id = playerInfo['mlbId']

    options =
      uri: "http://espn.go.com/mlb/player/splits/_/id/#{id}/year/2016/"
      json: true

    promiseRetry (retry, number) =>
      Promise.bind @
      .tap -> @logger.verbose "Fetch Extend2016Info info about player (#{id})"
      .then -> request options
      .tap -> @logger.verbose "Extend2016Info info about player (#{id}) has been successfully fetched"
      .then @parsePlayerExtendedInfo
      .then (stats) -> _.extend playerInfo.stats, {y2016extended: stats}
      .catch (error) ->
        @logger.error "Can't fetch data about player (#{id}). Attempt: #{number}", error
        retry(error)

  parsePlayerExtendedInfo: (data) ->

    $ = cheerio.load data
    stats = ["ab", "r", "h", "double", "triple", "hr", "rbi", "bb", "hbp", "so", "sb", "cs", "avg", "obp", "slg", "ops"]

    result = {}
    _.object $('.tablehead tr').each ->
      $row = $(@)

      values = _.map stats, (stat, index) ->
        # first position is a parameter name so just skip it
        position = index + 2
        $row.find(":nth-child(#{position})").text()

      row = _.object stats, values
      name = $row.find(':first-child').text().replace(/[^A-Z0-9]+/ig, "_").toLowerCase()

      result[name] = row

    result
