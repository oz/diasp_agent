http = require 'http'
https = require 'https'
querystring = require 'querystring'
jsdom  = require 'jsdom'
_ = require 'underscore'
fs = require 'fs'
path = require 'path'

bundleDir = path.dirname(module.filename)
bundle = fs.readFileSync("#{bundleDir}/ender.min.js").toString()

# EvilAgent
# =========
#
# EvilAgent performs HTTP requests like a true villain.
#
# It (mostly) wraps `jsdom` around node's native `http` module to
# automatically parse the HTTP responses (when they're some kind of HTML
# soup), and frees one from the pain of managing boring things like;
#
#   * Cookies
#   * DOM parsing (using jsdom)
#   * parameter encoding
#   * etc.
#
class EvilAgent
  constructor: (server, options = {}) ->
    server.ssl = server.port == 443
    @cookies = {}
    # Clone the received server param, and extend w/ other options.
    @options = _.extend (_.extend {}, server), options

  # Performs the HTTP request, receives a callback called when the
  # request is completed. The callback in turn must receive 3 parameters that
  # are:
  #
  #    * the native `HTTPResponse` object,
  #    * the response body, a `String`,
  #    * the parsed DOM, from jsdom.
  domReady: (fun) ->
    @performQuery @options, (res, body) ->
      jsdom.env
        html: body
        src: [ bundle ]
        done: (errors, window) ->
          fun res, body, window

  # Performs the HTTP request, receives a callback called when the
  # request is completed.  The callback in turn must receive 2 parameters
  # that are:
  #
  #   * the native `HTTPResponse` object,
  #   * the response body, a `String`.
  #
  # Note that the received callback will be called *regardless of the
  # HTTP status code*!
  complete: (fun) -> @performQuery @options, fun

  # Update @options
  update: (opts) -> @options = _.extend @options, opts

  # This is where the HTTP requests is made.
  performQuery: (options, cb) =>
    options.headers ?= {}
    body = ''
    payload = null
    client = if options.ssl is true then https else http

    # Fetch every cookies from the cookie jar.
    cookie = @__cookiesToString()
    if cookie then options.headers['Cookie'] = cookie

    # When sending a query with data, set the content-length, and
    # content-type headers: e.g. POST requests.
    if options.payload and options.method != 'GET'
      _.extend options.headers,
        'Content-Type': 'application/x-www-form-urlencoded'
        'Content-Length': options.payload.length

    req = client.request options, (res) =>
      res.setEncoding 'utf8'
      # Update the agent's cookie jar
      @__updateCookieJar res.headers['set-cookie']

      # Store response in a String (not a buffer)
      res.on 'data', (chunk) -> body += chunk
      res.on 'end', () -> cb res, body

    req.on 'error', (e) -> throw e

    # Send POST data if it was set.
    req.write options.payload if options.payload?
    req.end()

  # Set POST data
  postData: (data) ->
    if typeof data == 'string'
      @options.payload = data
    else
      @options.payload = querystring.stringify data

  # Cookie jar accessors
  setCookie: (key, value) -> @cookies[key] = value
  getCookie: (name) -> @cookies[name]

  # Updates the internal cookie jar with the cookies received in an
  # HTTPRequest response.
  __updateCookieJar: (cookies) ->
    _.extend @cookies, @__cookiesToObject cookies

  # Get all the cookies received by the latest response, and format them
  # to be sent in a 'Cookie' header.
  __cookiesToString: () -> _.map(@cookies, (v, k) -> "#{ k }=#{ v }").join ';'

  # Save each received cookie in a response to the @cookies jar.
  __cookiesToObject: (cookies) =>
    iterator = (memo, cookie) ->
      [key, value] = cookie.split(';')[0].split '=', 2
      memo[key] = value
      memo
    _.reduce cookies, iterator, {}

# DiasporaAgent
# =============
#
# DiasporaAgent is a boring web scraper using EvilAgent to do things
# like signing-in a D* node using... usernames and passwords. My bad.
#
# However, DiasporaAgent can pretty much act like a normal web client:
#
#   * post public messages,
#   * fetch your stream,
#   * etc.
#
# Limitations, evolutions
# -----------------------
#
# There is no public resource on D* to fetch a complete list of one's
# existing aspects ; as a consequence DiasporaAgent does not provide you
# with the tools to post a message to a specific aspect. So far!
#
class DiasporaAgent
  constructor: (@address, @password, @opts = {}) ->
    [@user, @host] = @address.split '@', 2
    port = if @opts.ssl? and @opts.ssl == false then 80 else 443
    port = @opts.port if @opts.port

    @server =
      host: @host
      port: port
    # Rails' anti-CSRF token
    @authenticityToken = null
    # Session cookie name
    @__sessionCookieName = '_diaspora_session'
    # Session cookie value
    @sessionCookie = null
    # Poor man's flag to indicate the need to call startSession
    @__sessionInitialized = false

  # Start the D* session: grab an authentication-token from an HTML
  # form, and register a session cookie from the HTTP responses...
  startSession: (cb) ->

    # Avoid initializing twice: if we've initialized our agent once,
    # then just call the received callback.
    return cb() if @__sessionInitialized
    @__sessionInitialized = true

    # Get the sign-in page...
    req = @get '/users/sign_in'

    # The HTML is parsed, and injected with Qwery and Bonzo to allow DOM
    # searches & other manipulations.
    req.domReady (res, body, dom) =>
      @authenticityToken = dom.$("meta[name=csrf-token]").attr 'content'
      @sessionCookie = req.getCookie @__sessionCookieName
      throw "Failed to find authenticity-token" unless @authenticityToken?
      throw "Failed to init. session cookie" unless @sessionCookie?

      # Once the page has been parsed, and we have saved the current
      # authenticity token, and session-cookie, call the received
      # callback.
      cb()

  # Sign in against the D* node, before calling the received callback.
  login: (cb) ->

    # Ensure we have a running session to get the initial anti-CSRF
    # token, and a session cookie.
    @startSession =>

      # POST the username and password to the D* sign-in URL in order to
      # create a new user-session.
      req = @post '/users/sign_in'
      req.postData
        'authenticity_token': @authenticityToken
        'user[username]':     @user
        'user[password]':     @password
        'user[remember_me]':  0
        'utf8':               '✓'

      req.complete (res, body) =>
        @sessionCookie = req.getCookie @__sessionCookieName

        # After sign-up, we should get redirected to the homepage...
        # XXX check res.location
        return cb message: 'Login failed' unless res.statusCode == 302
        cb null

        # ... which in turn redirects to the `/stream` page... Let's try
        # to load a faster page instead, because we need to update the
        # authenticity token & session cookie anyway.
        #redir = @get '/activity'
        #redir.domReady (res, body, dom) =>
          #@sessionCookie = redir.getCookie @__sessionCookieName
          #@authenticityToken = dom.$("meta[name=csrf-token]").attr 'content'
          #cb null

  # Post a public message to the connected D* account
  publicMessage: (text, cb) ->

    # Build a POST request for `/status_messages`.
    req = @post '/status_messages', 'Accept': 'application/json, text/javascript'
    req.postData 'status_message[text]': text, 'aspect_ids': 'public'
    req.complete (res, body) ->
      @sessionCookie = req.getCookie @__sessionCookieName

      # When a message resource is successfuly created, the response
      # code should be 201...
      if res.statusCode == 201
        cb null, JSON.parse body
      else
        cb {message: 'Message posting failed'}, null

  # `get` and `post` are wrappers for `__createRequest` to build GET and
  # POST HTTP requests.
  get:  (path, headers = {}) -> @__createRequest 'GET', path, headers
  post: (path, headers = {}) -> @__createRequest 'POST', path, headers

  # Get the connected user's stream page
  stream: (cb) ->
    @get('/stream.json').complete (res, body) ->
      cb {message: "Could not get the stream (#{ res.statusCode }) "} unless res.statusCode is 200
      cb null, JSON.parse body

  # Get the connected user's aspects page
  aspects: (cb) ->
    @get('/aspects.json').complete (res, body) ->
      cb {message: "Could not get the aspects (#{ res.statusCode }) "} unless res.statusCode is 200
      cb null, JSON.parse body

  # Create a new HTTP Request, whith the CSRF-Token and session cookie set.
  __createRequest: (method, path, headers={}) =>
    opts =
      method: method
      path: path
    opts.headers = 'X-CSRF-Token': @authenticityToken if @authenticityToken
    _.extend opts.headers, headers

    req = new EvilAgent @server, opts
    req.setCookie @__sessionCookieName, @sessionCookie

    # Return directly a new EvilAgent instance.
    req

  # Extract the value of a cookie against a list of received cookies. If
  # the cookie is not found, null is returned.
  __extractCookieValue: (cookies, name) ->
    find_name = (m, x) ->
      [key, value] = x.split(';')[0].split '=', 2
      m = value if name == key
    _.reduce cookies, find_name, null

module.exports = DiasporaAgent
