# TailscaleKitHello

## Instructions

First build TailscaleKit for the platform you wish to target:

From /swift:
```
$ make macos
$ make ios-fat
```

The ios target expects the universal xcframework produced by make ios-fat and
can be run on either a device or the simulator.

In TailnetSettings, configure a server/service to query.

```
let tailnetURL = "http://your-server-here.your-tailnet.ts.net"
```

Run the project.  With `authKey` left empty the app authenticates interactively:
it will display a login URL to open, which it picks up from the IPN bus as
`Ipn.Notify.BrowseToURL`.  Set `authKey` to a key from the admin console to skip
that step.  Do not commit a key.

If your tailnet requires device approval, the node waits in `NeedsMachineAuth`
until an admin approves it — the app shows the state so you can tell.

Once the node is up, Phone Home.  The output should be the response from the server.
