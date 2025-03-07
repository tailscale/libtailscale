# TailscaleKitHello

## Instructions

First build TailscaleKit:

From /swift:
```
$ make macos
```

In TailnetSettings, configure an auth key and a server/service to query.

```
let authKey = "your-auth-key-here"
let tailnetServer = "http://your-server-here.your-tailnet.ts.net"
```

Run the project.  Phone Home.  The output should be the response from the server.
