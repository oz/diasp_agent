# Diaspora Agent

DiasporaAgent is a node client for a
[Diaspora](https://github.com/diaspora/diaspora/) server.

It uses a combination of scraping, and `jsdom` to inject some `enderjs`
modules (namely, Qwery and Bonzo) in a perfectly idiotic way.

What did you say? OAuth? Never heard of it. :p

# Installation

```
npm install diasp_agent
```

# Usage

```javascript
var DiasporaAgent = require('diasp_agent')
  , d = new DiasporaAgent('user@joindiaspora.com', 'password')
  ;

d.login(function(err) {
  if (err) throw(err);
  console.log("Logged in, yay.");

  // Get the Aspects data
  d.aspects(function(err, aspects) {
    if (err) throw(err);

    console.log(aspects);
  });

  // Get the Stream data
  d.stream(function(err, stream) {
    if (err) throw(err);

    console.log(stream);
  });

  // Post a public message
  d.publicMessage("Hi, I'm a bot, and I'm #NewHere.", function(err, msg) {
    if (err) throw(err);

    console.log(msg);
  });
});

```

# Bugs and contributing

Obviously full of bugs, but I'll help fixing them.  If you find this
useful, please fork it and send some pull-requests.

# License

© 2012 Arnaud Berthomier

MIT, see the LICENSE file.
