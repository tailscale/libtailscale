#ifndef TSNETTEST
#define TSNETTEST

#include <errno.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "../tailscale.h"

#ifdef __cplusplus
extern "C"
{
#endif

    extern char *tmps1;
    extern char *tmps2;

    extern char *control_url;

    extern int addrlen;
    extern char *addr;
    extern char *proxy_cred;
    extern char *local_api_cred;

    extern int errlen;
    extern char *err;

    extern tailscale s1, s2;

    extern int set_err(tailscale sd, char tag);
    extern int test_conn();
    extern int close_conn();

#endif
#ifdef __cplusplus
}
#endif