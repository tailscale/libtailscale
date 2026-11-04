# tailscale

The tailscale gem provides an embedded network interface that can be used to
listen for and dial connections to other [Tailscale](https://tailscale.com)
nodes.

## Installation

Source installations will require a recent Go compiler in $PATH in order to build.

Install the gem and add to the application's Gemfile by executing:

    $ bundle add tailscale

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install tailscale

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

### Interrupting blocking calls

`up` and `dial` block until the node is usable (e.g. authorized). Both
methods stay responsive to interrupts while blocked: `Ctrl+C` in irb,
`Timeout.timeout`, or `Thread#raise` cancel the underlying Go call and
re-raise the interrupt. Both also take an optional `timeout:` (in seconds):

```ruby
t.up(timeout: 30)   # raises Tailscale::Error after 30 seconds
t.cancel            # or interrupt the most recent up/dial yourself
```

A `up` that was interrupted or timed out may leave the server partially
started; create a new `Tailscale` instance rather than retrying on the
same one.

### Signal handling

The gem loads a Go runtime as a shared library, which normally takes over
some process-global signal handling. libtailscale isolates this while it
loads (and the gem completes it with one call right after loading), so
Ruby's own signal handling (`Signal.trap`, `Ctrl+C`, `SystemStackError`)
keeps working unchanged. See [SIGNALS.md](../SIGNALS.md) in the
libtailscale repository for details.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Pull requests are welcome on GitHub at https://github.com/tailscale/libtailscale

Please file any issues about this code or the hosted service on
[the issue tracker](https://github.com/tailscale/tailscale/issues).
