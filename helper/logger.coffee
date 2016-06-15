util = require "util"
winston = require "winston"
loggly = require "winston-loggly"
sanitize = require "./sanitize"

winston.addColors
  verbose: "green"

module.exports = (options) ->
  transports = (new winston.transports[name](config) for name, config of options.transports)

  logger = new winston.Logger(
    transports: transports
  )

  logger.addRewriter (level, msg, meta) ->
    sanitize(meta, options.sanitizedProperties)

  logger
