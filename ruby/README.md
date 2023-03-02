# tailscale

The tailscale gem provides an embedded network interface that can be used to
listen for and dial connections to other [Tailscale](https://tailscale.com)
nodes.

## Installation

Source installations will require a recent Go compiler in $PATH in order to build.

Install the gem and add to the application's Gemfile by executing:

    $ bundle add tailscale

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install ailscale

## Usage

The node will need to be authorized in order to function. Set an auth key with
`set_auth_key`, or watch the libtailscale log stream and respond to the printed
authorization URL. You can also set the `$TS_AUTHKEY` environment variable.

```ruby
require 'tailscale'
t = Tailscale.new
t.up
l = t.listen "tcp", ":1999"
while c = l.accept
    c.write "hello world"
    c.close
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Pull requests are welcome on GitHub at https://github.com/tailscale/libtailscale

Please file any issues about this code or the hosted service on
[the issue tracker](https://github.com/tailscale/tailscale/issues).
