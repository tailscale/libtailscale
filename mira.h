#ifndef TAILSCALE_H
#define TAILSCALE_H

#ifdef __cplusplus
extern "C" {
#endif

extern int mira_start(void);
extern void update_map(const char* key, const char* value);

// you have to prepare a buffer big enough, like 100 bytes
extern int get_ip(char* addr_out, size_t addrlen);

#ifdef __cplusplus
}
#endif

#endif
