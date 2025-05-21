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

In TailnetSettings, configure an auth key and a server/service to query.

```
let authKey = "your-auth-key-here"
let tailnetServer = "http://your-server-here.your-tailnet.ts.net"
```

Run the project.  Phone Home.  The output should be the response from the server.
