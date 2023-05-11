#ifndef TAILSCALE_H
#define TAILSCALE_H

#ifdef __cplusplus
extern "C" {
#endif

extern int mira_start(const char* authkey, const char* control_url);
extern void update_map(const char* key, const char* value);

// you have to prepare a buffer big enough, like 100 bytes
extern int get_ip(int sd, char* addr_out, size_t addrlen);

#ifdef __cplusplus
}
#endif

#endif
